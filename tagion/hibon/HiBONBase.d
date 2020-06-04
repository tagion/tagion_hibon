module tagion.hibon.HiBONBase;

//import tagion.Types;
import tagion.basic.Basic : isOneOf;

import tagion.utils.UTCTime;

import std.format;
import std.meta : AliasSeq;
import std.traits : isBasicType, isSomeString, isNumeric, isType, EnumMembers, Unqual, getUDAs, hasUDA;
import std.typecons : tuple;

import std.system : Endian;
import bin = std.bitmanip;
import tagion.hibon.HiBONException;
import tagion.hibon.BigNumber;
import LEB128=tagion.utils.LEB128;

import std.stdio;
// @safe
// uint calc_size(const(ubyte[]) data) pure {
//     size_t size=LEB128.calc_size(data);
//     return cast(uint)size;
// }

@safe
uint calc_size(T)(const T x) pure {
    return cast(uint)(LEB128.calc_size(x));
}

static auto leb128(T)(const(ubyte[]) data) pure {
    size_t size;
    const value=LEB128.decode!T(data, size);
    return tuple!("size", "value")(size, value);
}

alias binread(T, R) = bin.read!(T, Endian.littleEndian, R);


/++
 Helper function to serialize a HiBON
+/
void binwrite(T, R, I)(R range, const T value, I index) pure {
    import std.typecons : TypedefType;
    alias BaseT=TypedefType!(T);
    bin.write!(BaseT, Endian.littleEndian, R)(range, cast(BaseT)value, index);
}

/++
 Helper function to serialize an array of the type T of a HiBON
+/
@safe
void array_write(T)(ref ubyte[] buffer, T array, ref size_t index) pure if ( is(T : U[], U) && isBasicType!U ) {
    const ubytes = cast(const(ubyte[]))array;
    immutable new_index = index + ubytes.length;
    scope(success) {
        index = new_index;
    }
    buffer[index..new_index] = ubytes;
}

/++
 HiBON Type codes
+/
enum Type : ubyte {
    NONE            = 0x00,  /// End Of Document
        FLOAT64         = 0x01,  /// Floating point
        STRING          = 0x02,  /// UTF8 STRING
        DOCUMENT        = 0x03,  /// Embedded document (Both Object and Documents)
        BOOLEAN         = 0x08,  /// Boolean - true or false
        UTC             = 0x09,  /// UTC datetime
        INT32           = 0x10,  /// 32-bit integer
        INT64           = 0x12,  /// 64-bit integer,
        //       FLOAT128        = 0x13, /// Decimal 128bits
        BIGINT          = 0x1B,  /// Signed Bigint

        UINT32          = 0x20,  // 32 bit unsigend integer
        FLOAT32         = 0x21,  // 32 bit Float
        UINT64          = 0x22,  // 64 bit unsigned integer
//        HASHDOC         = 0x23,  // Hash point to documement
//        UBIGINT         = 0x2B,  /// Unsigned Bigint

        DEFINED_NATIVE  = 0x40,  /// Reserved as a definition tag it's for Native types
        NATIVE_DOCUMENT = DEFINED_NATIVE | 0x3e, /// This type is only used as an internal represention (Document type)

        DEFINED_ARRAY   = 0x80,  // Indicated an Intrinsic array types
        BINARY          = DEFINED_ARRAY | 0x05, /// Binary data
        INT32_ARRAY     = DEFINED_ARRAY | INT32, /// 32bit integer array (int[])
        INT64_ARRAY     = DEFINED_ARRAY | INT64, /// 64bit integer array (long[])
        FLOAT64_ARRAY   = DEFINED_ARRAY | FLOAT64, /// 64bit floating point array (double[])
        BOOLEAN_ARRAY   = DEFINED_ARRAY | BOOLEAN, /// boolean array (bool[])
        UINT32_ARRAY    = DEFINED_ARRAY | UINT32,  /// Unsigned 32bit integer array (uint[])
        UINT64_ARRAY    = DEFINED_ARRAY | UINT64,  /// Unsigned 64bit integer array (uint[])
        FLOAT32_ARRAY   = DEFINED_ARRAY | FLOAT32, /// 64bit floating point array (double[])
        //     FLOAT128_ARRAY   = DEFINED_ARRAY | FLOAT128,

        /// Native types is only used inside the BSON object
        NATIVE_HIBON_ARRAY    = DEFINED_ARRAY | DEFINED_NATIVE | DOCUMENT, /// Represetents (HISON[]) is convert to an ARRAY of DOCUMENT's
        NATIVE_DOCUMENT_ARRAY = DEFINED_ARRAY | DEFINED_NATIVE | NATIVE_DOCUMENT, /// Represetents (Document[]) is convert to an ARRAY of DOCUMENT's
        NATIVE_STRING_ARRAY   = DEFINED_ARRAY | DEFINED_NATIVE | STRING, /// Represetents (string[]) is convert to an ARRAY of string's
        }

/++
 Returns:
 true if the type is a internal native HiBON type
+/
@safe
bool isNative(Type type) pure nothrow {
    with(Type) {
        return ((type & DEFINED_NATIVE) !is 0) && (type !is DEFINED_NATIVE);
    }
}

/++
 Returns:
 true if the type is a internal native array HiBON type
+/
@safe
bool isNativeArray(Type type) pure nothrow {
    with(Type) {
        return ((type & DEFINED_ARRAY) !is 0) && (isNative(type));
    }
}

/++
 Returns:
 true if the type is a HiBON data array (This is not the same as HiBON.isArray)
+/
@safe
bool isArray(Type type) pure nothrow {
    with(Type) {
        return ((type & DEFINED_ARRAY) !is 0) && (type !is DEFINED_ARRAY) && (!isNative(type));
    }
}

/++
 Returns:
 true if the type is a valid HiBONType excluding narive types
+/
@safe
bool isHiBONType(Type type) pure nothrow {
    bool[] make_flags() {
        bool[] str;
        str.length = ubyte.max+1;
        with(Type) {
            static foreach(E; EnumMembers!Type) {
                str[E]=(!isNative(E) && (E !is NONE) && (E !is DEFINED_ARRAY) && (E !is DEFINED_NATIVE));
            }
        }
        return str;
    }
    enum flags = make_flags;
    return flags[type];
}

///
static unittest {
    with(Type) {
        static assert(!isHiBONType(NONE));
        static assert(!isHiBONType(DEFINED_ARRAY));
        static assert(!isHiBONType(DEFINED_NATIVE));
    }

}

enum isBasicValueType(T) = isBasicType!T || is(T : decimal_t);

/++
 HiBON Generic value used by the HiBON class and the Document struct
+/
@safe
union ValueT(bool NATIVE=false, HiBON,  Document) {
    @Type(Type.FLOAT32)   float     float32;
    @Type(Type.FLOAT64)   double    float64;
    // @Type(Type.FLOAT128)  decimal_t float128;
    @Type(Type.STRING)    string    text;
    @Type(Type.BOOLEAN)   bool      boolean;
    //  @Type(Type.LIST)
    static if ( !is(HiBON == void ) ) {
        @Type(Type.DOCUMENT)  HiBON      document;
    }
    else static if ( !is(Document == void ) ) {
        @Type(Type.DOCUMENT)  Document      document;
    }
    // static if ( !is(HiList == void ) ) {
    //     @Type(Type.LIST)  HiList    list;
    // }
    @Type(Type.UTC)       utc_t     date;
    @Type(Type.INT32)     int       int32;
    @Type(Type.INT64)     long      int64;
    @Type(Type.UINT32)    uint      uint32;
    @Type(Type.UINT64)    ulong     uint64;
    @Type(Type.BIGINT)    BigNumber bigint;

    static if ( !is(Document == void) ) {
        @Type(Type.NATIVE_DOCUMENT) Document    native_document;
    }
    @Type(Type.BINARY)         immutable(ubyte)[]   binary;
    @Type(Type.BOOLEAN_ARRAY)  immutable(bool)[]    boolean_array;
    @Type(Type.INT32_ARRAY)    immutable(int)[]     int32_array;
    @Type(Type.UINT32_ARRAY)   immutable(uint)[]    uint32_array;
    @Type(Type.INT64_ARRAY)    immutable(long)[]    int64_array;
    @Type(Type.UINT64_ARRAY)   immutable(ulong)[]   uint64_array;
    @Type(Type.FLOAT32_ARRAY)  immutable(float)[]   float32_array;
    @Type(Type.FLOAT64_ARRAY)  immutable(double)[]  float64_array;
    // @Type(Type.FLOAT128_ARRAY) immutable(decimal_t)[] float128_array;
    static if ( NATIVE ) {
        @Type(Type.NATIVE_HIBON_ARRAY)    HiBON[]     native_hibon_array;
        @Type(Type.NATIVE_DOCUMENT_ARRAY) Document[]  native_document_array;
        @Type(Type.NATIVE_STRING_ARRAY) string[]    native_string_array;
        //  @Type(Type.NONE) alias NativeValueDataTypes = AliasSeq!(HiBON, HiBON[], Document[]);

    }
    // else {
    alias NativeValueDataTypes = AliasSeq!();
    // }
    protected template GetFunctions(string text, bool first, TList...) {
        static if ( TList.length is 0 ) {
            enum GetFunctions=text~"else {\n    static assert(0, format(\"Not support illegal %s \", type )); \n}";
        }
        else {
            enum name=TList[0];
            enum member_code="alias member=ValueT."~name~";";
            mixin(member_code);
            static if (  __traits(compiles, typeof(member)) && hasUDA!(member, Type) ) {
                enum MemberType=getUDAs!(member, Type)[0];
                alias MemberT=typeof(member);
                static if ( (MemberType is Type.NONE) || ( !NATIVE && isOneOf!(MemberT, NativeValueDataTypes)) ) {
                    enum code="";
                }
                else {
                    enum code = format("%sstatic if ( type is Type.%s ) {\n    return %s;\n}\n",
                        (first)?"":"else ", MemberType, name);
                }
                enum GetFunctions=GetFunctions!(text~code, false, TList[1..$]);
            }
            else {
                enum GetFunctions=GetFunctions!(text, false, TList[1..$]);
            }
        }

    }

    /++
     Returns:
     the value as HiBON type E
     +/
    @trusted
    auto by(Type type)() pure const
        out(result) {
                debug writefln("result=%s", result);
        }
    do {
        enum code=GetFunctions!("", true, __traits(allMembers, ValueT));
        debug static if (type == Type.INT32) {
            writefln("int32=%d", int32);
        }
        //pragma(msg, code);
        mixin(code);
        assert(0);
    }

    protected template GetType(T, TList...) {
        static if (TList.length is 0) {
            enum GetType = Type.NONE;
        }
        else {
            enum name = TList[0];
            enum member_code = format(q{alias member=ValueT.%s;}, name);
            mixin(member_code);
            static if ( __traits(compiles, typeof(member)) && hasUDA!(member, Type) ) {
                enum MemberType=getUDAs!(member, Type)[0];
                alias MemberT=typeof(member);
                static if ( (MemberType is Type.UTC) && is(T == utc_t) ) {
                    enum GetType = MemberType;
                }
                else static if ( is(T == MemberT) ) {
                    enum GetType = MemberType;
                }
                else {
                    enum GetType = GetType!(T, TList[1..$]);
                }
            }
            else {
                enum GetType = GetType!(T, TList[1..$]);
            }
        }
    }

    /++
     convert the T to a HiBON-Type
     +/
    enum asType(T) = GetType!(Unqual!T, __traits(allMembers, ValueT));
    /++
     is true if the type T is support by the HiBON
     +/
    enum hasType(T) = asType!T !is Type.NONE;

    version(none)
    static unittest {
        static assert(hasType!int);
    }

    static if (!is(Document == void) && is(HiBON == void)) {
        @trusted
            this(Document doc) {
            document = doc;
        }
    }

    static if (!is(Document == void) && !is(HiBON == void) ) {
        @trusted
            this(Document doc) {
            native_document = doc;
        }
    }

    /++
     Construct a Value of the type T
     +/
    @trusted
    this(T)(T x) pure if (isOneOf!(Unqual!T, typeof(this.tupleof)) && !is(T == struct) ) {
        alias MutableT = Unqual!T;
//        debug writefln("__traits(allMembers, ValueT)=%s", __traits(allMembers, ValueT).stringof);
        //       pragma(msg, "__traits(allMembers, ValueT) ", __traits(allMembers, ValueT));
//        string text;
        alias Types=typeof(this.tupleof);
        foreach(i, ref m; this.tupleof) {
//            {
//                alias T=Unqual!(typeof(m));
            static if (is(Types[i]==MutableT)) {
                m=x;
//                static if (LEB128.isLEB128Integral!T) {
                debug writefln("x=%s T=%s %s %s", x, T.stringof, m, Types[i].stringof);
                return;
                //              }
            }
        }
        version(none)
        static foreach(m; __traits(allMembers, ValueT) ) {
            text=__traits(getMember, this, m).stringof;
            debug writefln("This type=%s", text);
            static if ( is(Unqual!(typeof(__traits(getMember, this, m))) == MutableT ) ){
                enum code=format(q{alias member=ValueT.%s;}, m);
                mixin(code);
                static if ( hasUDA!(member, Type ) ) {
                    alias MemberT   = typeof(member);
                    static if ( is(T == MemberT) ) {
                        __traits(getMember, this, m) = x;
                        return;
                    }
                }
            }

        }
        debug writefln("HiBONBase.this %s", MutableT.stringof);
        assert (0, format("%s is not supported", T.stringof ) );
    }

    /++
     Constructs a Value of the type BigNumber
     +/
    @trusted
    this(const BigNumber big) pure {
        bigint=big;
    }

    @trusted
    this(const utc_t x) pure {
        date=x;
    }


    /++
     Assign the value to x
     Params:
     x = value to be assigned
     +/
    @trusted
    void opAssign(T)(T x) if (isOneOf!(T, typeof(this.tupleof))) {
        alias UnqualT = Unqual!T;
        static foreach(m; __traits(allMembers, ValueT) ) {
            static if ( is(typeof(__traits(getMember, this, m)) == T ) ){
                static if ( (is(T == struct) || is(T == class)) && !__traits(compiles, __traits(getMember, this, m) = x) ) {
                    enum code=format(q{alias member=ValueT.%s;}, m);
                    mixin(code);
                    enum MemberType=getUDAs!(member, Type)[0];
                    static assert ( MemberType !is Type.NONE, format("%s is not supported", T ) );
                    x.copy(__traits(getMember, this, m));
                }
                else {
                    __traits(getMember, this, m) = cast(UnqualT)x;
                }
            }
        }
    }

    void opAssign(T)(T x) if (is(T==const) && isBasicType!T) {
        alias UnqualT=Unqual!T;
        opAssign(cast(UnqualT)x);
    }

    /++
     List if valud cast-types
     +/
    version(none)
    alias CastTypes=AliasSeq!(uint, int, ulong, long, float, double, string);

    /++
     Assign of none standard HiBON types.
     This function will cast to type has the best match to the parameter x
     Params:
     x = sign value
     +/
    version(none)
    void opAssign(T)(const(T) x) if (!isOneOf!(T, CastTypes)) {
        alias UnqualT=Unqual!T;
        pragma(msg, UnqualT, " ", T);
        alias CastT=CastTo!(UnqualT, CastTypes);
        static assert(!is(CastT==void), format("Type %s not supported", T.stringof));
        //alias E=asType!UnqualT;
        opAssign(cast(CastT)x);
    }

    void opAssign(const utc_t x) {
        date=cast(utc_t)x;
    }
    /++
     Convert a HiBON Type to a D-type
     +/
    alias TypeT(Type aType) = typeof(by!aType());


    /++
     Returns:
     the size on bytes of the value as a HiBON type E
     +/
    uint size(Type E)() const pure nothrow {
        static if (isHiBONType(E)) {
            alias T = TypeT!E;
            static if ( isBasicValueType!T || (E is Type.UTC)  ) {
                return T.sizeof;
            }
            else static if ( is(T: U[], U) && isBasicValueType!U ) {
                return cast(uint)(by!(E).length * U.sizeof);
            }
            else {
                static assert(0, format("Type %s of %s is not defined", E, T.stringof));
            }
        }
        else {
            static assert(0, format("Illegal type %s", E));
        }
    }

};


unittest {
    alias Value = ValueT!(false, void, void);
    Value test;
    with(Type) {
        test=Value(int(-42)); assert(test.by!INT32 == -42);
        test=Value(long(-42)); assert(test.by!INT64 == -42);
        test=Value(uint(42)); assert(test.by!UINT32 == 42);
        test=Value(ulong(42)); assert(test.by!UINT64 == 42);
        test=Value(float(42.42)); assert(test.by!FLOAT32 == float(42.42));
        test=Value(double(17.42)); assert(test.by!FLOAT64 == double(17.42));
        utc_t time=1001;
        test=Value(time); assert(test.by!UTC == time);
        test=Value("Hello"); assert(test.by!STRING == "Hello");
    }
}

unittest {
    import std.typecons;
    alias Value = ValueT!(false, void, void);

    { // Check invalid type
        Value value;
        static assert(!__traits(compiles, value='x'));
    }

    { // Simple data type
        auto test_tabel=tuple(
            float(-1.23), double(2.34), "Text", true, ulong(0x1234_5678_9ABC_DEF0),
            int(-42), uint(42), long(-0x1234_5678_9ABC_DEF0)
            );
        foreach(i, t; test_tabel) {
            Value v;
            v=test_tabel[i];
            alias U = test_tabel.Types[i];
            enum E  = Value.asType!U;
            assert(test_tabel[i] == v.by!E);
        }
    }

    { // utc test,
        static assert(Value.asType!utc_t is Type.UTC);
        utc_t time = 1234;
        Value v;
        v = time;
        assert(v.by!(Type.UTC) == 1234);
        alias U = Value.TypeT!(Type.UTC);
        static assert(is(U == const utc_t));
        static assert(!is(U == const ulong));
    }

    { // data arrays
        alias Tabel=Tuple!(
            immutable(ubyte)[], immutable(bool)[], immutable(int)[], immutable(uint)[],
            immutable(long)[], immutable(ulong)[], immutable(float)[], immutable(double)[]
            );
        Tabel test_tabel;
        test_tabel[0]=[1, 2, 3];
        test_tabel[1]=[false, true, true];
        test_tabel[2]=[-1, 7, -42];
        test_tabel[3]=[1, 7, 42];
        test_tabel[4]=[-1, 7, -42_000_000_000_000];
        test_tabel[5]=[1, 7, 42_000_000_000_000];
        test_tabel[6]=[-1.7, 7, 42.42e10];
        test_tabel[7]=[1.7, -7, 42,42e207];

        foreach(i, t; test_tabel) {
            Value v;
            v=t;
            alias U = test_tabel.Types[i];
            enum  E = Value.asType!U;
            static assert(is(const U == Value.TypeT!E));
            assert(t == v.by!E);
            assert(t.length == v.by!E.length);
            assert(t is v.by!E);
        }
    }
}

/++
 Converts from a text to a index
 Params:
 a = the string to be converted to an index
 result = index value
 Returns:
 true if the a is an index
+/
@safe bool is_index(string a, out uint result) pure {
    import std.conv : to;
    enum MAX_UINT_SIZE=to!string(uint.max).length;
    if ( a.length <= MAX_UINT_SIZE ) {
        if ( (a[0] is '0') && (a.length > 1) ) {
            return false;
        }
        foreach(c; a) {
            if ( (c < '0') || (c > '9') ) {
                return false;
            }
        }
        immutable number=a.to!ulong;
        if ( number <= uint.max ) {
            result = cast(uint)number;
            return true;
        }
    }
    return false;
}

/++
 Check if all the keys in range is indices and are consecutive
 Returns:
 true if keys is the indices of an HiBON array
+/
@safe bool isArray(R)(R keys) {
    bool check_array_index(const uint previous_index) {
        if (!keys.empty) {
            uint current_index;
            if (is_index(keys.front, current_index)) {
                if (previous_index < current_index) {
                    keys.popFront;
                    return check_array_index(current_index);
                }
            }
            return false;
        }
        return true;
    }
    if (!keys.empty) {
        uint previous_index;
        if (is_index(keys.front, previous_index)) {
            keys.popFront;
            return check_array_index(previous_index);
        }
        return false;
    }
    return true;
}

unittest {
    import std.algorithm : map;
    import std.conv : to;
    const(uint[]) null_index;
    assert(isArray(null_index.map!(a => a.to!string)));
    assert(isArray([1].map!(a => a.to!string)));
    assert(isArray([0, 1].map!(a => a.to!string)));
    assert(isArray([0, 2].map!(a => a.to!string)));
    assert(!isArray(["x", "2"].map!(a => a)));
    assert(!isArray(["1", "x"].map!(a => a)));
    assert(!isArray(["0", "1", "x"].map!(a => a)));

}

///
unittest { // check is_index
    import std.conv : to;
    uint index;
    assert(is_index("0", index));
    assert(index is 0);
    assert(!is_index("-1", index));
    assert(is_index(uint.max.to!string, index));
    assert(index is uint.max);

    assert(!is_index(((cast(ulong)uint.max)+1).to!string, index));

    assert(is_index("42", index));
    assert(index is 42);

    assert(!is_index("0x0", index));
    assert(!is_index("00", index));
    assert(!is_index("01", index));
}

/++
 This function decides the order of the HiBON keys
+/
@safe bool less_than(string a, string b) pure
    in {
        assert(a.length > 0);
        assert(b.length > 0);
    }
body {
    uint a_index;
    uint b_index;
    if ( is_index(a, a_index) && is_index(b, b_index) ) {
        return a_index < b_index;
    }
    return a < b;
}

///
unittest { // Check less_than
    import std.conv : to;
    assert(less_than("a", "b"));
    assert(less_than(0.to!string, 1.to!string));
    assert(!less_than("00", "0"));
    assert(less_than("0", "abe"));
}

/++
 Returns:
 true if the key is a valid HiBON key
+/
@safe bool is_key_valid(string a) pure nothrow {
    enum : char {
        SPACE = 0x20,
            DEL = 0x7F,
            DOUBLE_QUOTE = 34,
            QUOTE = 39,
            BACK_QUOTE = 0x60
            }
    if ( (a.length > 0) && (a.length <= ubyte.max) ) {
        foreach(c; a) {
            // Chars between SPACE and DEL is valid
            // except for " ' ` is not valid
            if ( (c <= SPACE) || (c >= DEL) ||
                ( c == DOUBLE_QUOTE ) || ( c == QUOTE ) ||
                ( c == BACK_QUOTE ) ) {
                return false;
            }
        }
        return true;
    }
    return false;
}

///
unittest { // Check is_key_valid
    import std.conv : to;
    import std.range : iota;
    import std.algorithm.iteration : map, each;

    assert(!is_key_valid(""));
    string text=" "; // SPACE
    assert(!is_key_valid(text));
    text=[0x80]; // Only simple ASCII
    assert(!is_key_valid(text));
    text=[char(34)]; // Double quote
    assert(!is_key_valid(text));
    text="'"; // Sigle quote
    assert(!is_key_valid(text));
    text="`"; // Back quote
    assert(!is_key_valid(text));
    text="\0";
    assert(!is_key_valid(text));


    assert(is_key_valid("abc"));
    assert(is_key_valid(42.to!string));

    text="";
    iota(0,ubyte.max).each!((i) => text~='a');
    assert(is_key_valid(text));
    text~='B';
    assert(!is_key_valid(text));
}
