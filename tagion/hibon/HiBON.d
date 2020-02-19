/**
 * Implements HiBON
 * Hash-invariant Binary Object Notation
 * Is inspired by BSON but us not compatible
 *
 * See_Also:
 *  $(LINK2 http://bsonspec.org/, BSON - Binary JSON)
 *
 */
module tagion.hibon.HiBON;

import std.container : RedBlackTree;
import std.format;
import std.meta : staticIndexOf;
import std.algorithm.iteration : map, fold, each;
import std.traits : EnumMembers, ForeachType, Unqual, isMutable, isBasicType;
import std.meta : AliasSeq;
//import std.bitmanip : write;
import std.conv : to;
import std.typecons : TypedefType;

import tagion.hibon.BigNumber;
import tagion.hibon.Document;
import tagion.hibon.HiBONBase;
import tagion.hibon.HiBONException;
import tagion.Message : message;
import tagion.Base : CastTo;

@safe class HiBON {
    alias Value=ValueT!(true, HiBON,  Document);

    this() {
        _members = new Members;
    }

    size_t size() const pure {
        size_t result = uint.sizeof+Type.sizeof;
        if (_members.length) {
            result += _members[].map!(a => a.size).fold!( (a, b) => a + b);
        }
        return result;
    }

    immutable(ubyte[]) serialize() const pure {
        scope buffer = new ubyte[size];
        size_t index;
        append(buffer, index);
        return buffer.idup;
    }

    @trusted
    private void append(ref ubyte[] buffer, ref size_t index) const pure {
        immutable size_index = index;
        buffer.binwrite(uint.init, &index);
        if (_members.length) {
            _members[].each!(a => a.append(buffer, index));
        }
        buffer.binwrite(Type.NONE, &index);
        immutable doc_size=cast(uint)(index - size_index - uint.sizeof);
        buffer.binwrite(doc_size, size_index);
    }

    @safe static class Member {
        string key;
        Type type;
        Value value;

        protected this() pure nothrow {
            value = uint.init;
        }

        // this(T)(T x, string key) pure if ( is(T==Unqual!T) ) {
        //     this.value = x;
        //     this.type  = Value.asType!T;
        //     this.key  = key;
        // }
        alias CastTypes=AliasSeq!(uint, int, ulong, long, string);

        @trusted
        this(T)(T x, string key) { //const pure if ( is(T == const) ) {
            alias BaseT=TypedefType!T;
            alias UnqualT = Unqual!BaseT;
            enum E=Value.asType!UnqualT;
            this.key  = key;
            static if (E is Type.NONE) {
                alias CastT=CastTo!(UnqualT, CastTypes);
                static assert(!is(CastT==void), format("Type %s is not valid", T.stringof));
                alias CastE=Value.asType!CastT;
                this.type = CastE;
                this.value=cast(CastT)x;
            }
            else {
                this.type = E;
                static if (E is Type.BIGINT) {
                    this.value=x;
                }
                else {
                    this.value= cast(UnqualT)x;
                }
            }

        }

        @trusted
        inout(HiBON) document() inout pure
        in {
            assert(type is Type.DOCUMENT);
        }
        do {
            return value.document;
        }

        static Member search(string key) pure {
            auto result=new Member();
            result.key = key;
            return result;
        }

        const(T) get(T)() const {
            enum E = Value.asType!T;
            .check(E is type, message("Expected HiBON type %s but apply type %s (%s)", type, E, T.stringof));
            return value.by!E;
        }

        auto by(Type type)() inout {
            return value.by!type;
        }

        static const(Member) opCast(string key) pure {
            return Member.search(key);
        }

        @trusted
        size_t size() const pure {
            with(Type) {
            TypeCase:
                switch(type) {
                    foreach(E; EnumMembers!Type) {
                        static if(isHiBONType(E) || isNative(E)) {
                        case E:
                            static if ( E is Type.DOCUMENT ) {
                                return Document.sizeKey(key)+value.by!(E).size;
                            }
                            else static if ( E is NATIVE_DOCUMENT ) {
                                return Document.sizeKey(key)+value.by!(E).size+uint.sizeof;
                            }
                            else static if ( isNativeArray(E) ) {
                                size_t result = Document.sizeKey(key)+uint.sizeof+Type.sizeof;
                                foreach(i, e; value.by!(E)[]) {
                                    immutable key=i.to!string;
                                    result += Document.sizeKey(key);
                                    static if(E is NATIVE_HIBON_ARRAY) {
                                        result += e.size;
                                    }
                                    else static if (E is NATIVE_DOCUMENT_ARRAY) {
                                        result += uint.sizeof+e.size;
                                    }
                                    else static if (E is NATIVE_STRING_ARRAY) {
                                        result += uint.sizeof+e.length;
                                    }
                                }
                                return result;
                            }
                            else {
                                const v = value.by!(E);
                                return Document.sizeT(E, key, v);
                            }
                            break TypeCase;
                        }
                    }
                default:
                    // Empty
                }
                assert(0, format("Size of HiBON type %s is not valid", type));
            }
        }

        @trusted
        protected void appendList(Type E)(ref ubyte[] buffer, ref size_t index)  const pure if (isNativeArray(E)) {
            immutable size_index = index;
            buffer.binwrite(uint.init, &index);
            scope(exit) {
                buffer.binwrite(Type.NONE, &index);
                immutable doc_size=cast(uint)(index - size_index - uint.sizeof);
                buffer.binwrite(doc_size, size_index);
            }
            with(Type) {
                foreach(i, h; value.by!E) {
                    immutable key=i.to!string;
                    static if (E is NATIVE_STRING_ARRAY) {
                        Document.build(buffer, STRING, key, h, index);
                    }
                    else {
                        Document.buildKey(buffer, DOCUMENT, key, index);
                        static if (E is NATIVE_HIBON_ARRAY) {
                            h.append(buffer, index);
                        }
                        else static if (E is NATIVE_DOCUMENT_ARRAY) {
                            buffer.array_write(h.data, index);
                        }

                        else {
                            assert(0, format("%s is not implemented yet", E));
                        }
                    }
                }
            }

        }

        void append(ref ubyte[] buffer, ref size_t index) const pure {
            with(Type) {
            TypeCase:
                switch(type) {
                    static foreach(E; EnumMembers!Type) {
                        static if(isHiBONType(E) || isNative(E)) {
                        case E:
                            alias T = Value.TypeT!E;
                            static if (E is DOCUMENT) {
                                Document.buildKey(buffer, E, key, index);
                                value.by!(E).append(buffer, index);
                            }
                            else static if (isNative(E)) {
                                static if (E is NATIVE_DOCUMENT) {
                                    Document.buildKey(buffer, DOCUMENT, key, index);
                                    const doc=value.by!(E);
                                    buffer.array_write(value.by!(E).data, index);
                                }
                                else static if (isNativeArray(E)) {
                                    Document.buildKey(buffer, DOCUMENT, key, index);
                                    appendList!E(buffer, index);
                                }
                                else {
                                    goto default;
                                }
                            }
                            else {
                                Document.build(buffer, E, key, value.by!E, index);
                            }
                            break TypeCase;
                        }
                    }
                default:
                    assert(0, format("Illegal type %s", type));
                }
            }
        }
    }

    alias Members=RedBlackTree!(Member, (a, b) => (less_than(a.key, b.key)));

    protected Members _members;

    auto opSlice() const {
        return _members[];
    }

    void opIndexAssign(T)(T x, in string key) {
        .check(is_key_valid(key), message("Key is not a valid format '%s'", key));
        Member new_member=new Member(x, key);
        _members.insert(new_member);
    }

    void opIndexAssign(T)(T x, const size_t index) {
        const key=index.to!string;
        static if(!is(size_t == uint) ) {
            .check(index <= uint.max, message("Index out of range (index=%d)", index));
        }
        opIndexAssign(x, key);
    }

    const(Member) opIndex(in string key) const {
        auto range=_members.equalRange(Member.search(key));
        .check(!range.empty, message("Member '%s' does not exist", key) );
        return range.front;
    }

    const(Member) opIndex(const size_t index) const {
        const key=index.to!string;
        static if(!is(size_t == uint) ) {
            .check(index <= uint.max, message("Index out of range (index=%d)", index));
        }
        return opIndex(key);
    }

    bool hasMember(in string key) const {
        auto range=_members.equalRange(Member.search(key));
        return !range.empty;
    }

    @trusted
    void remove(string key) {
        _members.removeKey(Member.search(key));
    }

    unittest { // remove
        auto hibon=new HiBON;
        hibon["a"] =1;
        hibon["b"] =2;
        hibon["c"] =3;
        hibon["d"] =4;

        assert(hibon.hasMember("b"));
        hibon.remove("b");
        assert(!hibon.hasMember("b"));
    }

    size_t length() const {
        return _members.length;
    }

    auto keys() const {
        return map!"a.key"(this[]);
    }

    // Throws an std.conv.ConvException if the keys can not be convert to an uint
    auto indices() const {
        return map!"a.key.to!uint"(this[]);
    }

    bool isArray() const {
        return .isArray(keys);
    }

    unittest {
        {
            auto hibon=new HiBON;
            assert(!hibon.isArray);

            hibon["0"]=1;
            assert(hibon.isArray);
            hibon["1"]=2;
            assert(hibon.isArray);
            hibon["2"]=3;
            assert(hibon.isArray);
            hibon["x"]=3;
            assert(!hibon.isArray);
        }
        {
            auto hibon=new HiBON;
            hibon["1"]=1;
            assert(!hibon.isArray);
            hibon["0"]=2;
            assert(hibon.isArray);
            hibon["4"]=2;
            assert(!hibon.isArray);
        }
    }

    unittest {
        import std.stdio;
        import std.conv : to;
        import std.typecons : Tuple, isTuple;
        // Note that the keys are in alphabetic order
        // Because the HiBON keys must be ordered
        alias Tabel = Tuple!(
            BigNumber, Type.BIGINT.stringof,
            bool,   Type.BOOLEAN.stringof,
            float,  Type.FLOAT32.stringof,
            double, Type.FLOAT64.stringof,
            int,    Type.INT32.stringof,
            long,   Type.INT64.stringof,
            uint,   Type.UINT32.stringof,
            ulong,  Type.UINT64.stringof,

//                utc_t,  Type.UTC.stringof
            );

        Tabel test_tabel;
        test_tabel.FLOAT32 = 1.23;
        test_tabel.FLOAT64 = 1.23e200;
        test_tabel.INT32   = -42;
        test_tabel.INT64   = -0x0123_3456_789A_BCDF;
        test_tabel.UINT32   = 42;
        test_tabel.UINT64   = 0x0123_3456_789A_BCDF;
        test_tabel.BOOLEAN  = true;
        test_tabel.BIGINT   = BigNumber("-1234_5678_9123_1234_5678_9123_1234_5678_9123");

        // Note that the keys are in alphabetic order
        // Because the HiBON keys must be ordered
        alias TabelArray = Tuple!(
            immutable(ubyte)[],  Type.BINARY.stringof,
            immutable(bool)[],   Type.BOOLEAN_ARRAY.stringof,
            immutable(float)[],  Type.FLOAT32_ARRAY.stringof,
            immutable(double)[], Type.FLOAT64_ARRAY.stringof,
            immutable(int)[],    Type.INT32_ARRAY.stringof,
            immutable(long)[],   Type.INT64_ARRAY.stringof,
            string,              Type.STRING.stringof,
            immutable(uint)[],   Type.UINT32_ARRAY.stringof,
            immutable(ulong)[],  Type.UINT64_ARRAY.stringof,
            );
        TabelArray test_tabel_array;
        test_tabel_array.BINARY        = [1, 2, 3];
        test_tabel_array.FLOAT32_ARRAY = [-1.23, 3, 20e30];
        test_tabel_array.FLOAT64_ARRAY = [10.3e200, -1e-201];
        test_tabel_array.INT32_ARRAY   = [-11, -22, 33, 44];
        test_tabel_array.INT64_ARRAY   = [0x17, 0xffff_aaaa, -1, 42];
        test_tabel_array.UINT32_ARRAY  = [11, 22, 33, 44];
        test_tabel_array.UINT64_ARRAY  = [0x17, 0xffff_aaaa, 1, 42];
        test_tabel_array.BOOLEAN_ARRAY = [true, false];
        test_tabel_array.STRING        = "Text";

        { // empty
            auto hibon = new HiBON;
            assert(hibon.length is 0);

            assert(hibon.size is uint.sizeof+Type.sizeof);
            immutable data = hibon.serialize;

            const doc = Document(data);
            assert(doc.length is 0);
            assert(doc[].empty);
        }

        { // Single element
            auto hibon = new HiBON;
            enum pos=2;
            static assert(is(test_tabel.Types[pos] == float));
            hibon[test_tabel.fieldNames[pos]] = test_tabel[pos];

            assert(hibon.length is 1);

            const m=hibon[test_tabel.fieldNames[pos]];

            assert(m.type is Type.FLOAT32);
            assert(m.key is Type.FLOAT32.stringof);
            assert(m.get!(test_tabel.Types[pos]) == test_tabel[pos]);
            assert(m.by!(Type.FLOAT32) == test_tabel[pos]);

            immutable size = hibon.size;


            // This size of a HiBON with as single element of the type FLOAT32
            enum hibon_size
                = uint.sizeof                    // Size of the object in ubytes (uint(14))
                + Type.sizeof                    // The HiBON Type  (Type.FLOAT32)  1
                + ubyte.sizeof                   // Length of the key (ubyte(7))    2
                + Type.FLOAT32.stringof.length   // The key text string ("FLOAT32") 9
                + float.sizeof                   // The data            (float(1.23)) 13
                + Type.sizeof                    // The HiBON object ends with a (Type.NONE) 14
                ;

            const doc_size = Document.sizeT(Type.FLOAT32, Type.FLOAT32.stringof, test_tabel[pos]);

            assert(size is hibon_size);

            immutable data = hibon.serialize;

            const doc = Document(data);

            assert(doc.length is 1);
            const e = doc[Type.FLOAT32.stringof];

            assert(e.type is Type.FLOAT32);
            assert(e.key == Type.FLOAT32.stringof);
            assert(e.by!(Type.FLOAT32) == test_tabel[pos]);

        }

        { // HiBON Test for basic types
            auto hibon = new HiBON;

            string[] keys;
            foreach(i, t; test_tabel) {
                hibon[test_tabel.fieldNames[i]] = t;
                keys~=test_tabel.fieldNames[i];
            }

            size_t index;
            foreach(m; hibon[]) {
                assert(m.key == keys[index]);
                index++;
            }

            foreach(i, t; test_tabel) {
                enum key=test_tabel.fieldNames[i];
                const m = hibon[key];
                assert(m.key == key);
                assert(m.type.to!string == key);
                assert(m.get!(test_tabel.Types[i]) == t);
            }

            immutable data = hibon.serialize;
            const doc = Document(data);

            assert(doc.length is test_tabel.length);

            foreach(i, t; test_tabel) {
                enum key=test_tabel.fieldNames[i];
                const e = doc[key];
                assert(e.key == key);
                assert(e.type.to!string == key);
                assert(e.get!(test_tabel.Types[i]) == t);
            }
        }

        { // HiBON Test for basic-array types
            auto hibon = new HiBON;

            string[] keys;
            foreach(i, t; test_tabel_array) {
                hibon[test_tabel_array.fieldNames[i]] = t;
                keys~=test_tabel_array.fieldNames[i];
            }

            size_t index;
            foreach(m; hibon[]) {
                assert(m.key == keys[index]);
                index++;
            }

            foreach(i, t; test_tabel_array) {
                enum key=test_tabel_array.fieldNames[i];
                const m = hibon[key];
                assert(m.key == key);
                assert(m.type.to!string == key);
                assert(m.get!(test_tabel_array.Types[i]) == t);
            }

            immutable data = hibon.serialize;
            const doc = Document(data);

            assert(doc.length is test_tabel_array.length);

            foreach(i, t; test_tabel_array) {
                enum key=test_tabel_array.fieldNames[i];
                const e = doc[key];
                assert(e.key == key);
                assert(e.type.to!string == key);
                assert(e.get!(test_tabel_array.Types[i]) == t);
            }

        }

        { // HIBON test containg an child HiBON
            auto hibon = new HiBON;
            auto hibon_child = new HiBON;
            enum chile_name = "child";

            hibon["string"] = "Text";
            hibon["float"]  = float(1.24);

            immutable hibon_size_no_child = hibon.size;
            hibon[chile_name]      = hibon_child;
            hibon_child["int32"]= 42;

            immutable hibon_child_size    = hibon_child.size;
            immutable child_key_size = Document.sizeKey(chile_name);
            immutable hibon_size = hibon.size;
            assert(hibon_size is hibon_size_no_child+child_key_size+hibon_child_size);

            immutable data = hibon.serialize;
            const doc = Document(data);

        }

        { // Use of native Documet in HiBON
            auto native_hibon = new HiBON;
            native_hibon["int"] = int(42);
            immutable native_data = native_hibon.serialize;
            auto native_doc = Document(native_hibon.serialize);

            auto hibon = new HiBON;
            hibon["string"] = "Text";

            immutable hibon_no_native_document_size = hibon.size;
            hibon["native"] = native_doc;
            immutable data = hibon.serialize;
            const doc = Document(data);

            {
                const e = doc["string"];
                assert(e.type is Type.STRING);
                assert(e.get!string == "Text");
            }

            { // Check native document
                const e = doc["native"];

                assert(e.type is Type.DOCUMENT);
                const sub_doc =  e.get!Document;
                assert(sub_doc.length is 1);
                assert(sub_doc.data == native_data);
                const sub_e = sub_doc["int"];
                assert(sub_e.type is Type.INT32);
                assert(sub_e.get!int is 42);
            }
        }

        { // Document array
            HiBON[] hibon_array;
            alias TabelDocArray = Tuple!(
                int, "a",
                string, "b",
                float, "c"
                );
            TabelDocArray tabel_doc_array;
            tabel_doc_array.a=42;
            tabel_doc_array.b="text";
            tabel_doc_array.c=42.42;

            foreach(i, t; tabel_doc_array) {
                enum name=tabel_doc_array.fieldNames[i];
                auto local_hibon=new HiBON;
                local_hibon[name]=t;
                hibon_array~=local_hibon;
            }
            auto hibon = new HiBON;
            hibon["int"]  = int(42);
            hibon["array"]= hibon_array;

            immutable data = hibon.serialize;

            const doc = Document(data);

            {
                assert(doc["int"].get!int is 42);
            }

            {
                const doc_e =doc["array"];
                assert(doc_e.type is Type.DOCUMENT);
                const doc_array = doc_e.by!(Type.DOCUMENT);
                foreach(i, t; tabel_doc_array) {
                    enum name=tabel_doc_array.fieldNames[i];
                    alias U=tabel_doc_array.Types[i];
                    const doc_local=doc_array[i].by!(Type.DOCUMENT);
                    const local_e=doc_local[name];
                    assert(local_e.type is Value.asType!U);
                    assert(local_e.get!U == t);
                }
            }

            { // Test of Document[]
                Document[] docs;
                foreach(h; hibon_array) {
                    docs~=Document(h.serialize);
                }

                auto hibon_doc_array= new HiBON;
                hibon_doc_array["doc_array"]=docs;

                assert(hibon_doc_array.length is 1);

                immutable data_array=hibon_doc_array.serialize;

                const doc_all=Document(data_array);
                const doc_array=doc_all["doc_array"].by!(Type.DOCUMENT);

                foreach(i, t; tabel_doc_array) {
                    enum name=tabel_doc_array.fieldNames[i];
                    alias U=tabel_doc_array.Types[i];
                    alias E=Value.asType!U;
                    const e=doc_array[i]; //.get!U;
                    const doc_e=e.by!(Type.DOCUMENT);
                    const sub_e=doc_e[name];
                    assert(sub_e.type is E);
                    assert(sub_e.by!E == t);
                }

            }

        }

        {  // Test of string[]
            auto texts=["Hugo", "Vigo", "Borge"];
            auto hibon=new HiBON;
            hibon["texts"]=texts;

            immutable data=hibon.serialize;
            const doc=Document(data);
            const doc_texts=doc["texts"].by!(Type.DOCUMENT);

            assert(doc_texts.length is texts.length);
            foreach(i, s; texts) {
                const e=doc_texts[i];
                assert(e.type is Type.STRING);
                assert(e.get!string == s);
            }
        }
    }

}
