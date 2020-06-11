module tagion.hibon.BigNumber;

protected import std.bigint;
//import std.bigint;
import std.format;
import std.internal.math.biguintnoasm : BigDigit;
//import std.conv : emplace;
import std.range.primitives;
import std.traits;
import std.system : Endian;
import std.base64;
import std.exception : assumeUnique;

import tagion.hibon.HiBONException : check;
import tagion.hibon.BigNumber;

/++
 BigNumber used in the HiBON format
 It is a wrapper of the std.bigint
+/
@safe
struct BigNumber {
    private union {
        BigInt x;
        struct {
            BigDigit[] _data;
            bool _sign;
        }
    }


    /++
     Returns:
     the BigNumber as BigDigit array
     +/
    @trusted
    const(BigDigit[]) data() const pure nothrow {
        return _data;
    }

    /++
     Returns:
     the sign of the BigNumber
     +/
    @trusted
    bool sign() const pure nothrow {
        return _sign;
    }


    enum {
        ZERO=BigNumber(0), /// BigNumber zero
        ONE=BigNumber(1),  /// BigNumber one
        MINUSONE=BigNumber(-1) /// BigNumber negative one
    }

    /++
     Construct a BigNumber for an integer
     +/
    @trusted
    this(T)(T x) pure nothrow if (isIntegral!T) {
        this.x=BigInt(x);
    }

    /++
     Construct an number for a BigInt
     +/
    @trusted
    this(const(BigInt) x) pure nothrow {
        this.x=x;
    }

    /++
     Construct an number for a BigNumber
     +/
    @trusted
    this(const(BigNumber) big) pure nothrow {
        this.x=big.x;
    }


    /++
     Constructor from a number-string range
     +/
    @trusted
    this(Range)(Range s) if (
        isBidirectionalRange!Range &&
        isSomeChar!(ElementType!Range) &&
        !isInfinite!Range &&
        !isSomeString!Range) {
        this.x=BitInt(s);
    }

    /++
     Construct an BigNumber from a string of numbers
     +/
    @trusted
    this(Range)(Range s) pure if (isSomeString!Range) {
        this.x=BigInt(s);
    }


    /++
     Construct an BigNumber for explicit sign digit number array
     +/
    @trusted
    this(const bool sign, const(BigDigit[]) dig) {
        _sign=sign;
        _data=dig.dup;
    }

    @trusted this(const(ubyte[]) buffer) {
        const digits_len=buffer.length / BigDigit.sizeof;
        .check(digits_len > 0, "BigNumber must contain some digits");
        _data=(cast(BigDigit*)(buffer.ptr))[0..digits_len].dup;
        if (buffer.length % BigDigit.sizeof == 0) {
            _sign=false;
        }
        else if (buffer.length % BigDigit.sizeof == 1) {
            .check(buffer[$-1] is 0 || buffer[$-1] is 1,
                format("BigNuber has incorrect sign %d value should 0 or 1", buffer[$-1]));
            _sign=cast(bool)buffer[$-1];
        }
        else {
            .check(0, "Buffer does not have the correct size");
        }
    }
    /++
     Binary operator of op
     Params:
     y = is the right side value
     +/
    @trusted
    BigNumber opBinary(string op, T)(T y) pure nothrow const {
        static if (is(T:const(BigNumber))) {
            enum code=format("auto result=x %s y.x;", op);
        }
        else {
            enum code=format("auto result=x %s y;", op);
        }
        mixin(code);
    }

    /++
     Assign of the value x
     Params:
     x = value to be assigned
     Returns:
     The assign value as a BigNumber
     +/
    @trusted
    BigNumber opAssign(T)(T x) pure nothrow if (isIntegral!T) {
        this.x=x;
        return this;
    }

    /++
     Returns:
     the result of the unitary operation op
     +/
    @trusted
    BigNumber opUnary(string op)() pure nothrow const {
    }

    /++
     Operation assignment of the value y
     Params:
     y = value to be assigned
     Returns:
     The assign value as a BigNumber
     +/

    @trusted
    BigNumber opOpAssign(string op, T)(T y) pure nothrow {
        static if (is(T:const(BigNumber))) {
            enum code=format("this.x %s= y.x;", op);
        }
        else {
            enum code=format("this.x %s= y;", op);
        }
        mixin(code);
        return this;
    }

    /++
     Check the BigNumber has the equal value to y
     Params:
     y = value to be compared
     Returns:
     true if the values are equal
     +/
    @trusted
    bool opEquals()(auto ref const BigNumber y) const pure {
        return x == y.x;
    }

    /// ditto
    @trusted
    bool opEquals(T)(T y) const pure nothrow if (isIntegral!T) {
        return x == y;
    }

    /++
     Compare the BigNumber to y
     Params:
     y = value to be compared
     Returns:
     true if the values are equal
     +/
    @trusted
    int opCmp(ref const BigNumber y) pure nothrow const {
        return x.opCmp(y.x);
    }

    /// ditto
    @trusted
    int opCmp(T)(T y) pure nothrow const if (isIntegral!T) {
        return x.opCmp(x);
    }

    /// ditto
    @trusted
    int opCmp(T:BigNumber)(const T y) pure nothrow const {
        return x.opCmp(y.x);
    }

    /// cast BigNumber to a bool
    @trusted
    T opCast(T:bool)() pure nothrow const {
        return x.opCast!bool;
    }

    /// cast BigNumber to a type T
    @trusted
    T opCast(T:ulong)() pure const {
        return cast(T)x;
    }

    @trusted
    @property size_t ulongLength() const pure nothrow {
        return x.ulongLength;
    }

    /++
     Converts to type T
     +/
    @trusted
    T convert(T)() const if (isIntegral!T) {
        import std.conv : to;
        .check((x>=T.min) && (x<=T.max),
            format("Coversion range violation for type %s, value %s is outside the [%d..%d]",
                T.stringof, x, T.min, T.max));
        return x.to!T;
    }

    /++
     Coverts to a number string as a format
     +/
    @trusted
    void toString(scope void delegate(const (char)[]) sink, string formatString) const {
        return x.toString(sink, formatString);
    }

    /// ditto
    @trusted
    void toString(scope void delegate(const(char)[]) sink, const ref FormatSpec!char f) const {
        return x.toString(sink, f);
    }


    /++
     Coverts to a hexa-decimal number as a string as
     +/
    @trusted
    string toHex() const {
        return x.toHex;
    }

    /++
     Coverts to a decimal number as a string as
     +/
    @trusted
    string toDecimalString() const pure nothrow {
        return x.toDecimalString;
    }

    /++
     Coverts to a base64 format
     +/
    @trusted
    immutable(ubyte[]) serialize() const pure nothrow {
        immutable digits_size=BigDigit.sizeof*_data.length;
        auto buffer=new ubyte[digits_size+_sign.sizeof];
        buffer[0..digits_size]=cast(ubyte[])_data;
        buffer[$-1]=cast(ubyte)_sign;
        return assumeUnique(buffer);
    }

    version(none) {
        // working on LEB128 for big int
    TwoComplementRange two_complement() {
        static assert(BigDigit.sizeof is int.sizeof);
        return TwoComplementRange(this);
    }


    struct TwoComplementRange {
        protected {
            bool overflow;
            const(int)[] data;
            int current;
        }
        immutable bool sign;

        @disable this();
        this(const BigNumber num) {
            sign=num._sign;
            overflow=true;
            data=num._data;
        }

        @property {
            const pure nothrow {
                BigDigit front() {
                    return current;
                }
                bool empty() {
                    return data.length is 0;
                }
            }
            void popFront() {
            if (data.length) {
                if (sign) {
                    current=~data[0];
                    if (overflow) {
                        current++;
                        overflow=(current == 0);
                    }
                }
                else {
                    current=data[0];
                }
                data=data[1..$];
            }
        }
        }
    }

    immutable(ubyte[]) encodeLEB128() const pure nothrow {
        immutable DATA_SIZE=(BigDigit.sizeof*_data.length*8)/7+1;
        enum DIGITS_BIT_SIZE=BigDigit.sizeof*8;
        scope buffer=new ubyte[DATA_SIZE];
        size_t index;
        static assert(BigDigit.sizeof is int.sizeof);
        auto range2c=two_complement;

        long value=range2c.front;
        range2c.popFront;

        uint shift=DIGITS_BIT_SIZE;
        foreach(i, ref d; buffer) {
            d = value & 0x7F;
            shift-=7;
            if ((shift < 7) && (!range2c.empty)) {
                value |= (range2c.front << shift);
                shift+=DIGITS_BIT_SIZE;
                if (range2c.front & int.min) {
                    // Set sign bit
                    value |= (~0L) << shift;
                }
                range2c.popFront;
             }
            value >>= 7;
            //const uint uint_value=value & uint.max;
            if (((value == 0) && !(d & 0x40)) || ((value == -1) && (d & 0x40))) {
                return data[0..i+1].idup;
            }
            d |= 0x80;
        }
        assert(0);
    }

    size_t calc_size() const pure nothrow {
        immutable DATA_SIZE=(BigDigit.sizeof*_data.length*8)/7+1;
        enum DIGITS_BIT_SIZE=BigDigit.sizeof*8;
        size_t index;
        static assert(BigDigit.sizeof is int.sizeof);
        auto range2c=two_complement;

        long value=range2c.front;
        range2c.popFront;

        uint shift=DIGITS_BIT_SIZE;
        foreach(i; 0..DATA_SIZE) {
            scope d = value & 0x7F;
            shift-=7;
            if ((shift < 7) && (!range2c.empty)) {
                value |= (range2c.front << shift);
                shift+=DIGITS_BIT_SIZE;
                if (range2c.front & int.min) {
                    // Set sign bit
                    value |= (~0L) << shift;
                }
                range2c.popFront;
             }
            value >>= 7;
            if (((value == 0) && !(d & 0x40)) || ((value == -1) && (d & 0x40))) {
                return i;
            }
            d |= 0x80;
        }
        assert(0);
    }

    static BigNumber decodeLEB128(const(ubyte[]) data) {
        scope values=new BigDigits[data.length/BigDigits.length+1];
        enum DIGITS_BIT_SIZE=BigDigit.sizeof*8;
        long result;
        uint shift;
        foreach(i, d; data) {
            result |= (d & 0x7F) << shift;
            shift+=7;
            if (shift >= DIGITS_BIT_SIZE) {
                values[index++]=result & uint.max;
                result >>= DIGITS_BIT_SIZE;
            }
            if ((d & 0x80) == 0) {
                if ((d & 0x40) != 0) {
//                    resul
                }
            }
        }
    }
    }
}
