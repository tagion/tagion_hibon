module tagion.hibon.HiBONJSON;

//import std.stdio;

import std.json;
import std.conv : to;
import std.format;
import std.traits : EnumMembers, Unqual, ReturnType, ForeachType;
import std.range.primitives : isInputRange;
import std.base64;
import std.stdio;

import tagion.hibon.BigNumber;
import tagion.hibon.HiBONBase;
import tagion.hibon.HiBONException;
import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONtoText;

import tagion.basic.Message : message;
// import tagion.utils.JSONOutStream;
// import tagion.utils.JSONInStream : JSONType;

import tagion.basic.TagionExceptions : Check;
import tagion.utils.StdTime;

/**
 * Exception type used by tagion.hibon.HiBON module
 */
@safe
class HiBON2JSONException : HiBONException {
    this(string msg, string file = __FILE__, size_t line = __LINE__ ) pure {
        super( msg, file, line );
    }
}

alias check=Check!HiBON2JSONException;

enum NotSupported = "none";

protected Type[string] generateLabelMap(const(string[Type]) typemap) {
    Type[string] result;
    foreach(e, label; typemap) {
        if (label != NotSupported) {
            result[label]=e;
        }
    }
    return result;
}

enum typeMap=[
    Type.NONE       : NotSupported,
    Type.VER        : NotSupported,
    Type.FLOAT32    : "f32",
    Type.FLOAT64    : "f64",
    Type.STRING     : "$",
    Type.BINARY     : "*",
    Type.DOCUMENT   : "{}",
    Type.BOOLEAN    : "bool",
    Type.TIME       : "sdt",
    Type.INT32      : "i32",
    Type.INT64      : "i64",
    Type.UINT32     : "u32",
    Type.UINT64     : "u64",
    Type.BIGINT     : "big",
    Type.HASHDOC    : "#",
    // Type.CRYPTDOC   : "(#)",
    // Type.CREDENTIAL : "&",

    Type.DEFINED_NATIVE : NotSupported,

    Type.DEFINED_ARRAY         : NotSupported,
    Type.NATIVE_DOCUMENT       : NotSupported,
    Type.NATIVE_HIBON_ARRAY    : NotSupported,
    Type.NATIVE_DOCUMENT_ARRAY : NotSupported,
    Type.NATIVE_STRING_ARRAY   : NotSupported
    ];

static unittest {
    static foreach(E; EnumMembers!Type) {
        assert(E in typeMap, format("TypeMap %s is not defined", E));
    }
}
//    generateTypeMap;
enum labelMap=generateLabelMap(typeMap);


enum {
    TYPE=0,
    VALUE=1,
}

@safe
JSONValue toJSON(Document doc, bool hashsafe=true) {
    if (hashsafe) {
        return toJSONT!true(doc);
    }
    else {
        return toJSONT!false(doc);
    }
}

@safe
struct toJSONT(bool HASHSAFE) {
    @trusted
    static JSONValue opCall(const Document doc) {
        JSONValue result;
        immutable isarray=doc.isArray;
        if (isarray) {
            result.array=null;
            result.array.length=doc.length;
        }
        foreach(e; doc[]) {
            with(Type) {
            CaseType:
                switch(e.type) {
                    static foreach(E; EnumMembers!Type) {
                        static if (isHiBONType(E)) {
                        case E:
                            static if (E is DOCUMENT) {
                                const sub_doc=e.by!E;
                                auto doc_element=toJSONT(sub_doc);
                                if ( isarray ) {
                                    result.array[e.index]=JSONValue(doc_element);
                                }
                                else {
                                    result[e.key]=doc_element;
                                }
                            }
                            else static if ((E is BOOLEAN) || (E is STRING)) {
                                if ( isarray ) {
                                    result.array[e.index]=JSONValue(e.by!E);
                                }
                                else {
                                    result[e.key]=JSONValue(e.by!E);
                                }
                            }
                            else {
                                auto doc_element=new JSONValue[2];
                                doc_element[TYPE]=JSONValue(typeMap[E]);
                                if ( isarray ) {
                                    result.array[e.index]=toJSONType(e);
                                }
                                else {
                                    result[e.key]=toJSONType(e);
                                }
                            }
                            break CaseType;
                        }
                    }
                default:
                    .check(0, message("HiBON type %s notsupported and can not be converted to JSON", e.type));
                }
            }
        }
        return result;
    }

    static JSONValue[] toJSONType(Document.Element e) {
        auto doc_element=new JSONValue[2];
        doc_element[TYPE]=JSONValue(typeMap[e.type]);
        with(Type) {
        TypeCase:
            switch(e.type) {
                static foreach(E; EnumMembers!Type) {
                case E:
                    static if (E is BOOLEAN) {
                        doc_element[VALUE]=e.by!E;
                    }
                    else static if(E is INT32 || E is UINT32) {

                        doc_element[VALUE]=e.by!(E);
                    }
                    else static if(E is INT64 || E is UINT64) {
                        doc_element[VALUE]=format("0x%x", e.by!(E));
                    }
                    else static if((E is HASHDOC) || (E is BIGINT)) {
                        doc_element[VALUE]=encodeBase64(e.by!(E).serialize);
                    }
                    else static if(E is BINARY) {
                        doc_element[VALUE]=encodeBase64(e.by!(E));
                    }
                    else static if(E is FLOAT32 || E is FLOAT64) {
                        static if (HASHSAFE) {
                            doc_element[VALUE]=format("%a", e.by!E);
                        }
                        else {
                            doc_element[VALUE]=e.by!E;
                        }
                    }
                    else static if(E is TIME) {
                        doc_element[VALUE]=format("0x%x", e.by!(E));
                    }
                    else {
                        goto default;
                    }
                    break TypeCase;
                }
            default:
                throw new HiBONException(format("Unsuported HiBON type %s", e.type));
            }
        }
        return doc_element;
    }
}

HiBON toHiBON(scope const JSONValue json) {
    static const(T) get(T)(scope JSONValue jvalue) {
        alias UnqualT=Unqual!T;
        static if (is(UnqualT==bool)) {
            return jvalue.boolean;
        }
        else static if(is(UnqualT==uint)) {
            long x=jvalue.integer;
            .check((x>0) && (x<=uint.max), format("%s not a u32", jvalue));
            return cast(uint)x;
        }
        else static if(is(UnqualT==int)) {
            return jvalue.integer.to!int;
        }
        else static if(is(UnqualT==long) || is(UnqualT==ulong)) {
            const text=jvalue.str;
            ulong result;
            if (isHexPrefix(text)) {
                result=text[hex_prefix.length..$].to!ulong(16);
            }
            else {
                result=text.to!UnqualT;
            }
            static if (is(UnqualT==long)) {
                return cast(long)result;
            }
            else {
                return result;
            }
        }
        else static if(is(UnqualT==string)) {
            return jvalue.str;
        }
        else static if(is(T==immutable(ubyte)[])) {
            return decode(jvalue.str);
        }
        else static if(is(T:const(double))) {
            if (jvalue.type is JSONType.float_) {
                return jvalue.floating.to!UnqualT;
            }
            else {
                return jvalue.str.to!UnqualT;
            }
        }
        else static if(is(T:U[],U)) {
            scope array=new U[jvalue.array.length];
            foreach(i, ref a; jvalue) {
                array[i]=a.get!U;
            }
            return array.idup;
        }
        else static if (is(T : const BigNumber)) {
            const text=jvalue.str;
            if (isBase64Prefix(text) || isHexPrefix(text)) {
                const data=HiBONdecode(text);
                return BigNumber(data);
            }
            return BigNumber(jvalue.str);
        }
        else static if (is(T : const DataBlock)) {
            const buffer=HiBONdecode(jvalue.str);
            return T(buffer);
        }
        else static if (is(T : const sdt_t)) {
            return sdt_t(get!long(jvalue));
        }
        else {
            static assert(0, format("Type %s is not supported", T.stringof));
        }
        assert(0);
    }

    //static HiBON Obj(scope JSONValue json);
    static HiBON JSON(Key)(scope JSONValue json) {
        static bool set(ref HiBON sub_result, Key key, scope JSONValue jvalue) {
            if (jvalue.type is JSONType.string) {
                sub_result[key] = jvalue.str;
                return true;
            }
            else if ((jvalue.type is JSONType.true_) ||  (jvalue.type is JSONType.false_)) {
                sub_result[key] = jvalue.boolean;
                return true;
            }
            if (jvalue.array[TYPE].type !is JSONType.STRING) {
                return false;
            }
            immutable label=jvalue.array[TYPE].str;
            .check((label in labelMap) !is null, "HiBON type name '%s' is not valid", label);
            immutable type=labelMap[label];

            with(Type) {
                final switch(type) {
                    static foreach(E; EnumMembers!Type) {
                    case E:
                        static if (isHiBONType(E)) {
                            alias T=HiBON.Value.TypeT!E;
                            scope value=jvalue.array[VALUE];

                            static if(E is DOCUMENT) {
                                return false;
                            }
                            else {
                                static if(E is BINARY) {
                                    import std.uni : toLower;
                                    sub_result[key]=HiBONdecode(value.str).idup; //str[HEX_PREFIX.length..$]);
                                }
                                else {
                                    sub_result[key]=get!T(value);
                                }
                                return true;
                            }
                        }
                        else {
                            assert(0, format("Unsupported type %s for member %s", E, key));
                        }
                    }
                }
            }
            assert(0);
        }
        HiBON result=new HiBON;
        foreach(Key key, ref jvalue;json) {
            with(JSONType) {
                final switch(jvalue.type) {
                case null_:
                    .check(0, "HiBON does not support null");
                    break;
                case string:
                    result[key]=jvalue.str;
                    break;
                case integer:
                    result[key]=jvalue.integer;
                    break;
                case uinteger:
                    result[key]=jvalue.uinteger;
                    break;
                case float_:
                    result[key]=jvalue.floating;
                    break;
                case array:
                    if (!set(result, key, jvalue)) {
                        result[key]=Obj(jvalue);
                    }
                    break;
                case object:
                    result[key]=Obj(jvalue);
                    break;
                case true_:
                    result[key]=true;
                    break;
                case false_:
                    result[key]=false;
                    break;
                }
            }
        }
        return result;
    }

    static HiBON Obj(scope JSONValue json) {
        if ( json.type is JSONType.ARRAY ) {
            return JSON!size_t(json);
        }
        else if ( json.type is JSONType.OBJECT ) {
            return JSON!string(json);
        }
        .check(0, format("JSON_TYPE must be of %s or %s not %s", JSONType.OBJECT, JSONType.ARRAY, json.type));
        assert(0);
    }


    return Obj(json);
}

///
unittest {
    import tagion.hibon.HiBON : HiBON;
    import std.typecons : Tuple;
    alias Tabel = Tuple!(
        float,  Type.FLOAT32.stringof,
        double, Type.FLOAT64.stringof,
        bool,   Type.BOOLEAN.stringof,
        int,    Type.INT32.stringof,
        long,   Type.INT64.stringof,
        uint,   Type.UINT32.stringof,
        ulong,  Type.UINT64.stringof,
        BigNumber, Type.BIGINT.stringof,

        sdt_t,  Type.TIME.stringof
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
     test_tabel.TIME     = sdt_t(1001);

    alias TabelArray = Tuple!(
        immutable(ubyte)[],  Type.BINARY.stringof,
        string,              Type.STRING.stringof,
        DataBlock,             Type.HASHDOC.stringof,
        // Credential,          Type.CREDENTIAL.stringof,
        // CryptDoc,            Type.CRYPTDOC.stringof,
        );
    TabelArray test_tabel_array;
    test_tabel_array.BINARY        = [1, 2, 3];
    test_tabel_array.STRING        = "Text";
    test_tabel_array.HASHDOC       = DataBlock(27, [3,4,5]);
    // test_tabel_array.CRYPTDOC      = CryptDoc(42, [6,7,8]);
    // test_tabel_array.CREDENTIAL    = Credential(117, [9,10,11]);


    { // Test sample 1 HiBON Objects
        auto hibon=new HiBON;
        {
            foreach(i, t; test_tabel) {
                enum name=test_tabel.fieldNames[i];
                hibon[name]=t;
            }
            auto sub_hibon = new HiBON;
            hibon[sub_hibon.stringof]=sub_hibon;
            foreach(i, t; test_tabel_array) {
                enum name=test_tabel_array.fieldNames[i];
                sub_hibon[name]=t;
            }
        }

        //
        // Checks
        // HiBON -> Document -> JSON -> HiBON -> Document
        //
        const doc=Document(hibon.serialize);

        auto json=doc.toJSON(true);
        import std.stdio;
        // writefln("Before\n%s", json.toPrettyString);
        // writefln("%s", doc.data);
        string str=json.toString;
        auto parse=str.parseJSON;
        auto h=parse.toHiBON;

        const parse_doc=Document(h.serialize);
        // writefln("After\n%s", parse_doc.toJSON(true).toPrettyString);

        assert(doc == parse_doc);
        assert(doc.toJSON(true).toString == parse_doc.toJSON(true).toString);
    }

    { // Test sample 2 HiBON Array and Object
        auto hibon=new HiBON;
        {
            foreach(i, t; test_tabel) {
                enum name=test_tabel.fieldNames[i];
                hibon[i]=t;
            }
            auto sub_hibon = new HiBON;
            hibon[sub_hibon.stringof]=sub_hibon;
            foreach(i, t; test_tabel_array) {
                enum name=test_tabel_array.fieldNames[i];
                sub_hibon[i]=t;
            }
        }

        //
        // Checks
        // HiBON -> Document -> JSON -> HiBON -> Document
        //
        const doc=Document(hibon.serialize);

        auto json=doc.toJSON(true);
        import std.stdio;
        // writefln("Before\n%s", json.toPrettyString);
        // writefln("%s", doc.data);
        string str=json.toString;
        auto parse=str.parseJSON;
        auto h=parse.toHiBON;

        const parse_doc=Document(h.serialize);
        //      writefln("After\n%s", parse_doc.toJSON(true).toPrettyString);

        assert(doc == parse_doc);
        assert(doc.toJSON(true).toString == parse_doc.toJSON(true).toString);
    }

    { // Test sample 3 HiBON Array and Object
        auto hibon=new HiBON;
        {
            foreach(i, t; test_tabel) {
                enum name=test_tabel.fieldNames[i];
                hibon[i]=t;
            }
            auto sub_hibon = new HiBON;
            // Sub hibon is added to the last index of the hibon
            // Which result keep hibon as an array
            hibon[hibon.length]=sub_hibon;
            foreach(i, t; test_tabel_array) {
                enum name=test_tabel_array.fieldNames[i];
                sub_hibon[i]=t;
            }
        }

        //
        // Checks
        // HiBON -> Document -> JSON -> HiBON -> Document
        //
        const doc=Document(hibon.serialize);

        auto json=doc.toJSON(true);
        import std.stdio;
        // writefln("Before\n%s", json.toPrettyString);
        // writefln("%s", doc.data);

        string str=json.toString;
        auto parse=str.parseJSON;
        auto h=parse.toHiBON;

        const parse_doc=Document(h.serialize);
        //writefln("After\n%s", parse_doc.toJSON(true).toPrettyString);

        assert(doc == parse_doc);
        assert(doc.toJSON(true).toString == parse_doc.toJSON(true).toString);
    }
}
