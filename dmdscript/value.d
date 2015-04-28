/* Digital Mars DMDScript source code.
 * Copyright (c) 2000-2002 by Chromium Communications
 * D version Copyright (c) 2004-2010 by Digital Mars
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 * written by Walter Bright
 * http://www.digitalmars.com
 *
 * D2 port by Dmitry Olshansky
 *
 * Upgrading to EcmaScript 5.1 Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */

module dmdscript.value;

import std.math;

import std.string;
import std.stdio;
import std.c.string;

import dmdscript.script;
import dmdscript.dobject;
import dmdscript.iterator;
import dmdscript.identifier;
import dmdscript.errmsgs;
import dmdscript.protoerror;
import dmdscript.text;
import dmdscript.program;
import dmdscript.dstring;
import dmdscript.dnumber;
import dmdscript.dboolean;
import dmdscript.date;
import dmdscript.property;

// Porting issues:
// A lot of scaling is done on arrays of Value's. Therefore, adjusting
// it to come out to a size of 16 bytes makes the scaling an efficient
// operation. In fact, in some cases (opcodes.c) we prescale the addressing
// by 16 bytes at compile time instead of runtime.
// So, Value must be looked at in any port to verify that:
// 1) the size comes out as 16 bytes, padding as necessary
// 2) Value::copy() copies the used data bytes, NOT the padding.
//    It's faster to not copy the padding, and the
//    padding can contain garbage stack pointers which can
//    prevent memory from being garbage collected.

T Min(T)(T x, T y) {
    return (x<y)?x:y;
}

/**
   Due to a bug in std.math.pow, we have a pow wrapper
 */
d_number pow10(int n) {
    real x=10;
    bool reciproc;
    if (n<0) {
        n=-n;
        reciproc=true;
    }
    switch (n) {
    case 0:
        return 1.0;
    case 1:
        return x;
    case 2:
        return x * x;
    default:
    }
    real p=1.0;
    while (1) {
        if (n & 1)
            p *= x;
        n >>= 1;
        if (!n)
            break;
        x *= x;
    }
    if (reciproc) p=1.0/p;
    std.stdio.writeln("x=",x-0.0001," 0.1^4=", 0.1*0.1*0.1*0.1*0.1*0.1*0.1*0.1-1e-8," 1/(10*10*10*10)=",(1.0/(10.0*10.0*10.0*10.0*10.0*10.0*10.0*10.0))-1e-8);
    std.stdio.writeln(p-1e-4);
    std.stdio.writeln("---x=",(17*p)-17*1e-4);
    return cast(d_number)p;
}


unittest {
    assert(pow10(0) == 1);
    assert(pow10(1) == 10);
    assert(pow10(2) == 100);
    assert(pow10(-1) == 0.1);
    assert(pow10(-2) == 0.01);
    assert(pow10(15) == 1e15);
    assert(pow10(-15) == 1e-15);
    assert(pow10(-4) == 1e-4);
    assert(17*pow10(-4) == 17e-4);

}

version(DigitalMars)
    version(D_InlineAsm)
        version = UseAsm;

enum vtype_t : ubyte
{
    V_REF_ERROR = 0,//triggers ReferenceError excpetion when accessed
    V_UNDEFINED = 1,
    V_NULL      = 2,
    V_BOOLEAN   = 3,
    V_NUMBER    = 4,
    V_INTEGER   = 5,
    V_STRING    = 6,
    V_OBJECT    = 7,
    V_ITER      = 8,
    V_ACCESSOR  = 9,
}

version(D_LP64)
    enum jam_hash_mask = 0x5555_5555_5555_5555;
else
    enum jam_hash_mask = 0x5555_5555;

alias Value* delegate(Value* caller, Value* ret, Value* arg) Setter;

struct Value
{
    static Value vundefined =  { _vtype : vtype_t.V_UNDEFINED, protect : 0 };
    static Value vnull      =  { _vtype : vtype_t.V_NULL, protect : 0 };

    static invariant() {
        assert(vundefined._vtype is vtype_t.V_UNDEFINED);
        assert(vnull._vtype is vtype_t.V_NULL);
        //assert();
    }
    private vtype_t _vtype = vtype_t.V_UNDEFINED;
    ushort protect; // This value is used by the Identifer get
                    // information of the property attributes
    union { // The hash value for a getter is not used so we reuse the
            // memory for the getter
        hash_t  hash;                 // cache 'hash' value
        Value* getter; // Call able function for the getter
    }
    union
        {
            d_boolean _dbool;        // can be true or false
            d_number  _number;
            d_string  _string;
            Dobject   _object;
            d_int32   int32;
            d_uint32  uint32;
            d_uint16  uint16;
            Value*  setter;         // Call able for function for setter
            Iterator* iter;         // V_ITER
        }

    static Value opCall(T)(T x) {
        Value result;
        result=x;
        return result;
    }

    static void xdump() {
       std.stdio.writeln("_vtype.offsetof=",_vtype.offsetof);
       std.stdio.writeln("hash.offsetof=",hash.offsetof);
       std.stdio.writeln("number.offsetof=",_number.offsetof);
       std.stdio.writeln("protect.offsetof=",protect.offsetof);
       std.stdio.writeln("Value.sizeof=",Value.sizeof);
       std.stdio.writeln("number.sizeof=",_number.sizeof);
    }

    // invariant()  {
    //     if (protect) {
    //         std.stdio.writeln("protect=",protect);
    //     }
    //     //assert((protect & ReadOnly)!=0);
    // }

    @property vtype_t vtype() const pure {
        return _vtype;
    }

    @property d_boolean dbool() const
    in {
        assert(_vtype is vtype_t.V_BOOLEAN);
    }
    body {
        return _dbool;
    }

    @property d_number number() const
    in {
        assert(_vtype is vtype_t.V_NUMBER || _vtype is vtype_t.V_INTEGER);
    }
    body {
        return _number;
    }

    @property d_number number(d_number num)
    in {
        assert(_vtype is vtype_t.V_NUMBER);
    }
    body {
        _number=num;
        return _number;
    }

    @property Dobject object()
        in {
        if (_vtype !is vtype_t.V_OBJECT) {
            std.stdio.writeln("Not an object");
        }
        assert(_vtype is vtype_t.V_OBJECT);
    } body {
        return _object;
    }

    @property d_string string() const
        in {
        assert(_vtype is vtype_t.V_STRING);
    } body {
        return _string;
    }


    void checkReference() const {
        if(vtype == vtype_t.V_REF_ERROR)
            throwRefError();
    }

    void throwRefError() const{
        throw new ErrorValue(Dobject.ReferenceError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_UNDEFINED_VAR],_string));
    }

    void putSignalingUndefined(d_string id){
        _vtype = vtype_t.V_REF_ERROR;
        _string = id;
        hash = 0;
    }

    void putVundefined()
        {
            _vtype = vtype_t.V_UNDEFINED;
            hash = 0;
            _string = null;
        }

    void putVnull()
        {
            _vtype = vtype_t.V_NULL;
            hash = 0;
        }

    void putVboolean(T)(T b)
        {
            _vtype = vtype_t.V_BOOLEAN;
            _dbool = (b)?true:false;
            hash = 0;
        }

    void putVnumber(d_number n)
        {
            _vtype = vtype_t.V_NUMBER;
            _number = n;
            hash = 0;
        }

    void putVuint32(d_uint32 n)
        {
            _vtype = vtype_t.V_INTEGER;
            uint32 = n;
            hash = 0;
        }

    void putVtime(d_time n)
        {
            _vtype = vtype_t.V_NUMBER;
            _number = (n == d_time_nan) ? d_number.nan : n;
            hash = 0;
        }

/*
    void putVstring(T)(T s) if (is(T == typeof(null))) {
        _vtype = vtype_t.V_STRING;
        hash = 0;
        _string=null;
    }

    void putVstring(T)(T s) if (is(T == d_string) ) {
        _vtype = vtype_t.V_STRING;
        hash = 0;
        _string=s;
    }

    void putVstring(T)(T s) if ( is(T == immutable(char)[]) ) {
        _vtype = vtype_t.V_STRING;
        hash = 0;
        _string=toDstring(s);
    }
*/

    void putVstring(T)(T s, hash_t hash=0)
        in {
        static if (is(T == d_string) ) assert(( hash == 0) || (hash == calcHash(s)));
        else assert(hash == 0,"Hash should not be specified for non "~d_string.stringof~" Types ");
      } body {
        _vtype = vtype_t.V_STRING;
        this.hash = hash;

        if (s is null) {
            _string=null;
        } else static if ( is(T == d_string) ) {
            _string=s;
        } else static if ( is( T : const(char)[] ) ) {
            _string = toDstring(s);
        } else static if ( is( T.toText ) ) {
            _string = x.toText;
        } else {
           static assert(0, "Type "~T.stringof~"Not supported by putVstring");
        }
    }
/*
    void putVstring(d_string s, hash_t hash)
        in
        {
            assert(hash == calcHash(s));
        }
        body
        {
            _vtype = vtype_t.V_STRING;
            this.hash = hash;
            this._string = s;
        }
*/
    void putVobject(Dobject o)
        {
            _vtype = vtype_t.V_OBJECT;
            _object = o;
            hash = 0;
        }

    void putViterator(Iterator* i)
        {
            _vtype = vtype_t.V_ITER;
            iter = i;
            hash = 0;
        }

    package void putVSetter(Value* setter)
    in {
        assert( (setter is null) || setter.isObject);
        // Getter must be an Object type
        assert( (_vtype !is vtype.V_ACCESSOR) || ((setter is null) || setter.isObject) );
    }
    body
    {
        if (_vtype !is vtype_t.V_ACCESSOR) {
            this.getter=null;
            _vtype=vtype_t.V_ACCESSOR;
        }

        if (setter) {
            this.setter=new Value;
            copy(this.setter, setter);
        } else {
            this.setter=null;
        }
    }

    package void putVGetter(Value* getter)
    in {
        // Getter must be an Object type
        assert( (getter is null) || getter.isObject);
        assert( (_vtype !is vtype.V_ACCESSOR) || ((getter is null) || getter.isObject) );
    }
    body
    {
        if (_vtype !is vtype_t.V_ACCESSOR) {
            this.setter=null;
            _vtype=vtype_t.V_ACCESSOR;
        }
        _vtype=vtype_t.V_ACCESSOR;
        if (getter) {
            this.getter=new Value;
            copy(this.getter, getter);
        } else {
            this.getter=null;
        }
    }

    void opAssign(T)(T value) {
        static if (is(T : Dobject)) {
            putVobject(value);
        } else static if (is(T == bool)) {
                putVboolean(value);
        } else static if (is(T : d_uint32)) {
                putVuint32(value);
        } else static if (is(T : d_number)) {
                putVnumber(value);
        } else static if (is(T : d_string)) {
                putVstring(value);
        } else static if (is(T : const(char)[])) {
                putVstring(value);
        } else static if (is(T==Value)) {
                copyTo(&value);
        } else static if (is(T==Value*)) {
                copyTo(value);
        } else static if (is(T==const Value)) {
                copyTo(&value);
        } else {
                static assert(0, "Type "~T.stringof~" is not supported by dmdscript");
                putVundefined;
        }
    }

    void charAt(d_uint32 index, Value* ret) {
        d_string s=toText;
        if ( !isUndefinedOrNull && index < s.length ) {
            immutable(wchar)[] result;
            result~=s[index];
            ret.putVstring(result);
        } else {
            ret.putVundefined;
        }
    }

    unittest {
        Value value;
        Dobject obj=new DobjectPrototype;
        value=20;
        assert(value.toInteger==20);
        value=13.3;
        assert(value.toNumber==13.3);
        value="test";
        assert(value.toText=="test");
        value=obj;
        assert(value.toObject is obj);
        value=true;
        assert(value.toText=="true");
        value=false;
        assert(value.toText=="false");
    }

    Value* callSet(CallContext* cc, Dobject othis, Value* ret, Value[] arglist)
    in{
        assert(isAccessor);
    }
    out{
        assert(isAccessor);
    }
    body{
        if (setter) {
            Value* result=setter.Call(cc, othis, ret, arglist);
            if (result) {
                throw new ErrorValue(result);
            }
            return result;

        }
        ret.putVundefined;
        return null;
    }

    Value* callGet(CallContext* cc, Dobject othis, Value* ret)
    in {
        assert(isAccessor);
    }
    out(result) {
        assert(isAccessor);
    }
    body {
        if (getter) {
            Value* result=getter.Call(cc, othis, ret, null);
            if (result) {
                throw new ErrorValue(result);
            }
            return result;
        }
        ret.putVundefined;
        return null;
    }

    unittest {
        // Hash
        Value a,b,c;
        a="22";
        b=22;
        c=22.0;
        assert(a.toHash == b.toHash);
        assert(a.toHash == c.toHash);
        assert(b.toHash == c.toHash);
        a=4294967295;
        b="4294967295";
        assert(a.toHash == b.toHash);
        a=4294967296;
        b="4294967296";
        assert(a.toHash == b.toHash);
        a=4294967297;
        b="4294967297";
        assert(a.toHash == b.toHash);
    }

    static void copy(Value* to, const(Value)* from)
        in
        {
            assert(to !is null);
            assert(from !is null);
        }
    body
        {
            memcpy(to, from, Value.sizeof);
            to.protect=0;
        }

    static Value* check(Value* value) {
        return (value)?value:&vundefined;
    }

    Value* toPrimitive(Value* v, d_string PreferredType) {
        if(vtype is vtype_t.V_OBJECT) {
            /*	ECMA 9.1
                Return a default value for the Object.
                The default value of an object is retrieved by
                calling the internal [[DefaultValue]] method
                of the object, passing the optional hint
                PreferredType. The behavior of the [[DefaultValue]]
                method is defined by this specification for all
                native ECMAScript objects (see section 8.6.2.6).
                If the return value is of type Object or Reference,
                a runtime error is generated.
            */
            Value* a;

            assert(object);
            a = object.DefaultValue(v, PreferredType);
            if(a) {
                return a;
            }
            if(!v.isPrimitive())
            {
                v.putVundefined();
                return Dobject.RuntimeError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_OBJECT_CANNOT_BE_PRIMITIVE]);
            }
        }
        else {
            copy(v, &this);
        }
        return null;
    }

    d_boolean toBoolean() const
        {
            with (vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return false;
            case V_BOOLEAN:
                return _dbool;
            case V_NUMBER:
                return !(_number == 0.0 || isNaN(_number));
            case V_INTEGER:
                return int32 != 0;
            case V_STRING:
                return _string.length ? true : false;
            case V_OBJECT:
                return true;
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
            assert(0);
        }


    private d_number toDouble() const {
        assert(vtype == vtype_t.V_INTEGER || vtype == vtype_t.V_NUMBER);
        if (vtype == vtype_t.V_INTEGER) {
            return cast(double)int32;
        }
        return _number;
    }

    d_number toNumber() const
        in {
        if (!isPrimitive) {
            std.stdio.writeln("toNumber not a primitive");
        }
        assert(isPrimitive);
    } body {
        with(vtype_t) final switch(_vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
                return d_number.nan;
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return _dbool ? 1 : 0;
            case V_NUMBER:
                return number;
            case V_INTEGER:
                return cast(d_number)int32;
            case V_STRING:
            {
                d_number n;
                size_t len;
                size_t endidx;

                len = _string.length;
                if ( len == 0 ) return 0.0;
                n = StringNumericLiteral(_string, endidx, 0);

                // Consume trailing whitespace
                // writefln("n = %s, string = '%s', endidx = %s, length = %s", n, string, endidx, string.length);
                foreach(dchar c; _string[endidx .. $])
                {
                    if(!isStrWhiteSpaceChar(c))
                    {
                        n = d_number.nan;
                        break;
                    }
                }

                return n;
            }
            case V_OBJECT:
            case V_ACCESSOR:
            case V_ITER:
                assert(0, "toNumber const does not support type "~vtype.stringof);
            }
        assert(0);
    }

    d_number toNumber() {
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
                return d_number.nan;
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return _dbool ? 1 : 0;
            case V_NUMBER:
                return number;
            case V_INTEGER:
                return cast(d_number)int32;
            case V_STRING:
            {
                d_number n;
                size_t len;
                size_t endidx;

                len = _string.length;
                if ( len == 0 ) return 0.0;
                n = StringNumericLiteral(_string, endidx, 0);

                // Consume trailing whitespace
                // writefln("n = %s, string = '%s', endidx = %s, length = %s", n, string, endidx, string.length);
                foreach(dchar c; _string[endidx .. $])
                {
                    if(!isStrWhiteSpaceChar(c))
                    {
                        n = d_number.nan;
                        break;
                    }
                }

                return n;
            }
            case V_OBJECT:
            { Value val;
                Value* v;
                void* a;

                //writefln("Vobject.toNumber()");
                v = &val;
                a = toPrimitive(v, TypeNumber);
                /*if(a)//rerr
                  return d_number.nan;*/
                if(v.isPrimitive())
                    return v.toNumber();
                else
                    return d_number.nan;
            }
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
        assert(0);
    }


    d_time toDtime()
        {
            return cast(d_time)toNumber();
        }

/*
    d_number toInteger()
        {
            with(vtype_t) final switch(vtype) {
                case V_REF_ERROR:
                    throwRefError();
                case V_UNDEFINED:
                    return d_number.nan;
                case V_NULL:
                    return 0;
                case V_BOOLEAN:
                    return _dbool ? 1 : 0;
                case V_NUMBER:
                case V_INTEGER:
                case V_STRING:
                case V_OBJECT:
                case V_ITER:
                { d_number num;

                        num = toNumber();
                        if(isnan(num))
                            num = 0;
                        else if(num == 0 || std.math.isinf(num))
                        {
                        }
                        else if(num > 0)
                            num = std.math.floor(num);
                        else
                            num = -std.math.floor(-num);
                        return num; }
                case V_ACCESSOR:
                    assert(0);
                }

            assert(0);
        }
*/
    d_number toInteger() const
        {
            with(vtype_t) final switch(vtype) {
                case V_REF_ERROR:
                    throwRefError();
                case V_UNDEFINED:
                    return d_number.nan;
                case V_NULL:
                    return 0;
                case V_BOOLEAN:
                    return _dbool ? 1 : 0;
                case V_NUMBER:
                case V_INTEGER:
                case V_STRING:
                case V_OBJECT:
                case V_ITER:
                { d_number num;

                        num = toNumber();
                        if(isNaN(num))
                            num = 0;
                        else if(num == 0 || std.math.isInfinity(num))
                        {
                        }
                        else if(num > 0)
                            num = std.math.floor(num);
                        else
                            num = -std.math.floor(-num);
                        return num; }
                case V_ACCESSOR:
                    assert(0);
                }

            assert(0);
        }


    d_int32 toInt32()
        {
            with(vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return _dbool ? 1 : 0;
            case V_INTEGER:
                return int32;
            case V_NUMBER:
            case V_STRING:
            case V_OBJECT:
            case V_ITER:
            { d_int32 int32;
                    d_number num;
                    long ll;

                    num = toNumber();
                    if(isNaN(num))
                        int32 = 0;
                    else if(num == 0 || std.math.isInfinity(num))
                        int32 = 0;
                    else
                    {
                        if(num > 0)
                            num = std.math.floor(num);
                        else
                            num = -std.math.floor(-num);

                        ll = cast(long)num;
                        int32 = cast(int)ll;
                    }
                    return int32; }
            case V_ACCESSOR:
            }
            assert(0);
        }


    d_uint32 toUint32() {
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return _dbool ? 1 : 0;
            case V_INTEGER:
                return cast(d_uint32)int32;
            case V_NUMBER:
            case V_STRING:
            case V_OBJECT:
            case V_ITER:
                d_uint32 uint32;
                d_number num;
                long ll;

                num = toNumber();
                if(isNaN(num))
                    uint32 = 0;
                else if(num == 0 || std.math.isinf(num))
                    uint32 = 0;
                else
                {
                    if(num > 0)
                        num = std.math.floor(num);
                    else
                        num = -std.math.floor(-num);

                    ll = cast(long)num;
                    uint32 = cast(uint)ll;
                }
                return uint32;
            case V_ACCESSOR:
                assert(0, "Accessor");
            }
        assert(0);
    }

    d_uint32 toUint32() const {
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return _dbool ? 1 : 0;
            case V_INTEGER:
                return cast(d_uint32)int32;
            case V_NUMBER:
            case V_STRING:
            case V_OBJECT:
            case V_ITER:
                d_uint32 uint32;
                d_number num;
                long ll;

                num = toNumber();
                if(isNaN(num))
                    uint32 = 0;
                else if(num == 0 || std.math.isinf(num))
                    uint32 = 0;
                else
                {
                    if(num > 0)
                        num = std.math.floor(num);
                    else
                        num = -std.math.floor(-num);

                    ll = cast(long)num;
                    uint32 = cast(uint)ll;
                }
                return uint32;
            case V_ACCESSOR:
            }
        assert(0);
    }

    d_uint16 toUint16() {
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return cast(d_uint16)(_dbool ? 1 : 0);
            case V_INTEGER:
                return cast(d_uint16)(int32 & 0xFFFF);
            case V_NUMBER:
            case V_STRING:
            case V_OBJECT:
            case V_ITER:
            { d_uint16 uint16;
                    d_number num;

                    num = toNumber();
                    if(isNaN(num))
                        uint16 = 0;
                    else if(num == 0 || std.math.isinf(num))
                        uint16 = 0;
                    else
                    {
                        if(num > 0)
                            num = std.math.floor(num);
                        else
                            num = -std.math.floor(-num);

                        uint16 = cast(ulong)num & 0xFFFF;
                    }
                    return uint16; }
            case V_ACCESSOR:
            }
        assert(0);
    }

    d_uint16 toUint16() const {
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return cast(d_uint16)(_dbool ? 1 : 0);
            case V_INTEGER:
                return cast(d_uint16)(int32 & 0xFFFF);
            case V_NUMBER:
            case V_STRING:
            case V_OBJECT:
            case V_ITER:
            { d_uint16 uint16;
                    d_number num;

                    num = toNumber();
                    if(isNaN(num))
                        uint16 = 0;
                    else if(num == 0 || std.math.isinf(num))
                        uint16 = 0;
                    else
                    {
                        if(num > 0)
                            num = std.math.floor(num);
                        else
                            num = -std.math.floor(-num);

                        uint16 = cast(ulong)num & 0xFFFF;
                    }
                    return uint16; }
            case V_ACCESSOR:
            }
        assert(0);
    }

    d_string toText() const
        in {
        assert(isPrimitive);
    } body {
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
                return TEXT_undefined;
            case V_NULL:
                return TEXT_null;
            case V_BOOLEAN:
                return _dbool ? TEXT_true : TEXT_false;
            case V_NUMBER:
                return numberToString(number);
            case V_INTEGER:
                return numberToString(int32);
            case V_STRING:
                return _string;
            case V_OBJECT:
            case V_ACCESSOR:
            case V_ITER:
                assert(0, "toText const does not support "~_vtype.stringof);
            }
        assert(0);
    }

    d_string toText()
        {
            with(vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
                return TEXT_undefined;
            case V_NULL:
                return TEXT_null;
            case V_BOOLEAN:
                return _dbool ? TEXT_true : TEXT_false;
            case V_NUMBER:
                return numberToString(number);
            case V_INTEGER:
                return numberToString(int32);
            case V_STRING:
                return _string;
            case V_OBJECT:
            { Value val;
                    Value* v = &val;
                    void* a;

                    //writef("Vobject.toText()\n");
                    a = toPrimitive(v, TypeString);
                    //assert(!a);
                    if(v.isPrimitive())
                        return v.toText();
                    else
                        return v.toObject().classname;
            }
            case V_ACCESSOR:
                return toInfo;
            case V_ITER:
                assert(0);
            }
            assert(0);
        }

    /*
      This function is used for to debug instead of toText
     */
    d_string toInfo() const {
        d_string buf;
        d_string dataInfo() {
            with(vtype_t) switch(vtype) {
                case V_REF_ERROR:
                    return "[ERROR]";
                case V_UNDEFINED:
                    return TEXT_undefined;
                case V_NULL:
                    return TEXT_null;
                case V_BOOLEAN:
                    return _dbool ? TEXT_true : TEXT_false;
                case V_NUMBER:
                    return numberToString(number);
                case V_INTEGER:
                    return numberToString(int32);
                case V_STRING:
                    return _string;
                case V_OBJECT:
                    return "[Object]";
                case V_ACCESSOR:
                    return dmdscript.script.format("[Set=%x Get=%x]",setter,getter);
                case V_ITER:
                    return "[Iterator]";
                default:
                    return "[Invalid]";
                }
        }
        if (protect) {
            return dataInfo~Property.toInfo(protect);
        } else {
            return dataInfo;
        }
    }


    d_string toLocaleString()
        {
            return toText();
        }

    d_string toText(int radix)
        {
            if(vtype == vtype_t.V_NUMBER)
            {
                assert(2 <= radix && radix <= 36);
                if(!isFinite(number))
                    return toText();
                return number >= 0.0 ? std.conv.to!(d_string)(cast(long)number, radix) : "-"~std.conv.to!(d_string)(cast(long)-number,radix);
            }
            else
            {
                return toText();
            }
        }

    d_string toSource(Dobject root)
        {
            with(vtype_t) final switch(vtype)
            {
            case V_STRING:
            { d_string s;

                    s = "\"" ~ _string ~ "\"";
                    return s; }
            case V_OBJECT:
            { Value* v;

                if (root is _object) {
                    return "[Circular]";
                }
                //writefln("Vobject.toSource()");
                v = Get(TEXT_toSource);
                if(!v)
                    v = &vundefined;
                if(v.isPrimitive())
                    return v.toSource(root);
                else          // it's an Object
                {
                    void* a;
                    CallContext *cc;
                    Dobject o;
                    Value* ret;
                    Value val;

                    o = v.object;
                    cc = Program.getProgram().callcontext;
                    ret = &val;
                    a = o.Call(cc, this.object, ret, null);
                    if(a)                             // if exception was thrown
                    {
                        /*return a*/;
                        writef("Vobject.toSource() failed with %x\n", a);
                    }
                    else if(ret.isPrimitive())
                        return ret.toText();
                }
                return TEXT_undefined; }
            case V_REF_ERROR:
            case V_UNDEFINED:
            case V_NULL:
            case V_BOOLEAN:
            case V_INTEGER:
            case V_NUMBER:
            case V_ITER:
            case V_ACCESSOR:
                return toText();
            }
            assert(0);
        }


    static bool stringToLong(d_string val, out long x) {
        x=0;
        if (val.length == 0) return false;
        foreach(c ; val) {
            if (c >= '0' && c <= '9') {
                x*=10;
                x+=cast(long)(c-'0');
            } else {
                return false;
            }
        }
        return true;
    }

    d_string numberToString() const {
        with(vtype_t) switch(vtype) {
            case V_INTEGER:
                return numberToString(uint32);
            case V_NUMBER:
                return numberToString(number);
            default:
                return TEXT_NaN;
            }
    }

    static d_string numberToString(double number) {
//    short n;
        long s;
        real m;
        d_string buffer;
        // char* p=buffer.ptr;
        static enum d_string  digittext[10] =
            [   TEXT_0, TEXT_1, TEXT_2, TEXT_3, TEXT_4,
                TEXT_5, TEXT_6, TEXT_7, TEXT_8, TEXT_9 ];
        immutable(d_string) digitchar=
            TEXT_0~TEXT_1~TEXT_2~TEXT_3~TEXT_4~
            TEXT_5~TEXT_6~TEXT_7~TEXT_8~TEXT_9;
        static assert(digitchar.length == 10);
        //   writefln("Vnumber.tostr(%.16f)", number);
        if(isNaN(number))
            buffer = TEXT_NaN;
        // else if(number >= 0 && number <= 9 && number == cast(int)number)
        //     buffer = digittext[cast(int)number];
        else if(std.math.isinf(number))
        {
            if(number < 0)
                buffer = TEXT_negInfinity;
            else
                buffer = TEXT_Infinity;
        }
        else
        {
            if (number < 0.0) {
                buffer~='-';
                m=-cast(real)number;
            } else {
                m=cast(real)number;
            }

            ulong sintx;
            if ( ( ( sintx = cast(ulong)m) == m ) ) {
                void toInt(ulong s) {
                    if ( s != 0 ) {
                        toInt(s/10);
                        buffer~=digittext[s % 10];
                    }
                }
                if ( sintx == 0 ) {
                    buffer~=digittext[0];
                } else {
                    toInt(sintx);
                }
            } else {
                real err;

                short k=1;
                short n=0;
                n=cast(short)(std.math.log10(m));
                // n=cast(short)((n<0)?(n):(n+1));
                n=cast(short)(n+1);

                long sfloor=-1;
                short search_k(in short k, in real _err, in real k_n_exp) {
                    if (k-n+d_number.min_10_exp>0) return k;

                    if ( k>=21 ) return 21;
//        real neg_exp=std.math.pow(10.0, k-n);
//        real k_exp=std.math.pow(10.0, k);
                    real sval=m*k_n_exp;
                    s=cast(long)std.math.round(sval);
                    if ( sfloor == -1 ) {
                        sfloor=cast(long)sval;
                        // if ( s != sfloor ) writeln("round s=",s," sfloor=",sfloor);
                    } else {
                        sfloor=s;
                    }

                    err=std.math.abs(1.0-s/(m*k_n_exp));
//        writefln("neg_exp=%g k_n_exp=%g", neg_exp, k_n_exp);
//         writefln("k=%d n=%d err=%.19f s=%19.f k_exp=%g neg_exp=%g", k, n, err,s,k_exp,neg_exp);
                    // if ( !( s>=std.math.pow(10.0, k-1) && s<std.math.pow(10.0,k)) ) writeln("fail Within");
                    // if ( !( s<std.math.pow(10.0,k)) ) writeln("fail higher");
                    // if ( !( s>=std.math.pow(10.0, k-1) ) ) writeln("fail lower");
                    //    assert( s>=std.math.pow(10.0, k-1) && s<std.math.pow(10.0,k) );
                    if ( s == 0 || s != sfloor ) {
                        n--;
                        return search_k(k,err,std.math.pow(10.0, k-n));
                    } else if ( err > 1e-16 || err < _err ) {
                        //    writefln("err -_err=%.19f",err-_err);
                        return search_k(cast(short)(k+1),err,k_n_exp*10.0);
                    } else if ( k == 1  && !( s<std.math.pow(10.0,k) ) ) {
                        n++;
                        return search_k(k,err,std.math.pow(10.0, k-n));
                    } else {
                        return cast(short)(k);
                    }
                }
                real sreal;
                k=1;
              Lretry:
                k=search_k(k, 1.0, std.math.pow(10.0, k-n));

                real neg_exp=std.math.pow(10.0, k-n);
                sreal=std.math.round(m*neg_exp);
                if (sreal.isinf) {
                    buffer~='0';
                    goto Lreturn;
                }
                assert(!sreal.isinf);
                // write("--> k=",k," n=",n," s*10^(n-k)=",sreal);
                // writeln(" m*neg_exp=",sreal*std.math.pow(10.0,n-k));

                //sint=cast(ulong)std.math.round(m*neg_exp);
                if ( !(sreal < std.math.pow(10.0,k) ) ) {
                    n++;
                    if (n >-20 ) goto Lretry;
                }


                wchar digchar(in real sval) {
                    size_t digindex=cast(size_t)(sval/10);
                    digindex*=10;
                    digindex=cast(size_t)(sval-digindex);
                    if ( sval > 9 ) buffer~=digchar(sval/10);
                    return digitchar[digindex];
                }

                if ( k <= n && n <= 21 ) {
                    // writeln("k<=n<=21");
                    buffer~=digchar(sreal);
                    foreach (i;k..n ) buffer~='0';

                    if ( 0 < n && n <= 21  && k-n > 0 ) {
                        buffer~='.';
                        buffer~=digchar(sreal);
                    }
                }
                else if ( -6 < n && n <= 0 ) {
                    // writeln("-6<n<=0");
                    buffer~="0.";
                    foreach (i;0..-n ) buffer~='0';
                    buffer~=digchar(sreal);
                    while (buffer[$-1]=='0') buffer=buffer[0..$-1];
                }
                else if ( k == 1 ) {
                    buffer~=digchar(sreal);
                    while (buffer[$-1]=='0' ) {
                        buffer=buffer[0..$-1];
                        n++;
                    }
                    buffer~='e';
                    if ( (n-1) > 0 ) {
                        buffer~='+';
                        buffer~=digchar(n-1);
                    } else {
                        buffer~='-';
                        buffer~=digchar(1-n);
                    }
                }
                else {
                    // writeln("otherwise");
                    auto point=buffer.length;
                    buffer~=digchar(sreal);
                    if ( n > 1  && buffer.length-point >= n ) {
                        point+=n;
                        n=1;
                    } else if ( n > 1 && n-k+buffer.length-point <= 22 ) {
                        point+=n;
                        n=1;
                    } else {
                        point+=1;
                    }
                    //  writefln("buffer.length=%d point=%d buffer=%s %f", buffer.length, point, buffer, sreal);

                    if (buffer.length > point ) {
                        buffer=buffer[0..point]~'.'~buffer[point..$];
                        // Not the nice hack but it works (Deletes traling .0)
                        while ( buffer[$-1]=='0' ) buffer=buffer[0..$-1];
                        if ( buffer[$-1]=='.' ) buffer=buffer[0..$-1];
                    } else if ( buffer.length < point  ) {
                        foreach(i;0..point-buffer.length) buffer~='0';
                    }

                    if ( n != 1 ) {
                        buffer~='e';
                        if ( (n-1) > 0 ) {
                            buffer~='+';
                            buffer~=digchar(n-1);
                        } else {
                            buffer~='-';
                            buffer~=digchar(1-n);
                        }
                    }
                }
            }
        }
      Lreturn:
        return buffer.idup;
    }

    unittest {
        assert(numberToString(0) == "0");
        assert(numberToString(double.infinity) == "Infinity");
        assert(numberToString(-double.infinity) == "-Infinity");
        assert(numberToString(double.nan) == "NaN");
        assert(numberToString(1) == "1");
        assert(numberToString(9) == "9");
        assert(numberToString(-1) == "-1");
        assert(numberToString(-9) == "-9");
        assert(numberToString(13) == "13");
        assert(numberToString(16) == "16");

        assert(numberToString(12345) == "12345");
        assert(numberToString(0.12345) == "0.12345");

        //writeln(numberToString(0.5));
        assert(numberToString(0.49) == "0.49");
        assert(numberToString(0.55) == "0.55");
        assert(numberToString(51627) == "51627");
        assert(numberToString(0.51627) == "0.51627");
        assert(numberToString(0.051627) == "0.051627");
        assert(numberToString(0.0051627) == "0.0051627");
        assert(numberToString(0.00051627) == "0.00051627");
        assert(numberToString(0.000051627) == "0.000051627");


        assert(numberToString(1e20) == "100000000000000000000");
        assert(numberToString(1e21) == "1000000000000000000000");
        assert(numberToString(1e22) == "1e+22");
        assert(numberToString(1e-5) == "0.00001");
        assert(numberToString(1.2e-6) == "0.0000012");
        assert(numberToString(1e-7) == "1e-7");

        assert(numberToString(12.345e-203) == "1.2345e-202");
        assert(numberToString(12.345e0203) == "1.2345e+204");
        assert(numberToString(1152921504606846976) == "1152921504606846976");
        assert(numberToString(1152921504606846976) == "1152921504606846976");

        assert(numberToString(cast(real)(0x1000000000000000)*0x10) == "18446744073709551616" );
        assert(numberToString(cast(real)(0x1000000000000000)*0x100) == "295147905179352825800" );
        assert(numberToString(cast(real)(0x1000000000000000)*0x1000) == "4722366482869645600000" );
        assert(numberToString(cast(real)(0x1000000000000000)*0x10000) == "7.555786372591432499e+22");

        assert(numberToString(-cast(real)(0x1000000000000000)*0x10) == "-18446744073709551616" );
        assert(numberToString(-cast(real)(0x1000000000000000)*0x100) == "-295147905179352825800" );
        assert(numberToString(-cast(real)(0x1000000000000000)*0x1000) == "-4722366482869645600000" );
        assert(numberToString(-cast(real)(0x1000000000000000)*0x10000) == "-7.555786372591432499e+22");

        assert(numberToString(1.1) == "1.1" );
        assert(numberToString(-1.1) == "-1.1" );
        assert(numberToString(0.000001) == "0.000001" );
        // Small value is prited as zero
        assert(numberToString(Dnumber.MIN_VALUE*1e5)=="0");
        assert(numberToString(Dnumber.MIN_VALUE)=="0");
        assert(numberToString(-Dnumber.MIN_VALUE*1e5)=="-0");
        assert(numberToString(-Dnumber.MIN_VALUE)=="-0");
    }

/*
    static d_number stringToNumber(d_string string, bool parsefloat=false, int[d_string] exptable=null) {
        d_string rest;
        return stringToNumber(string, rest, parsefloat, exptable);
    }

    static d_number stringToNumber(d_string string, out d_string rest, bool parsefloat=false, int[d_string] exptable=null) {
        d_string s=string;
        real x=0;
        bool sign;
        while(s.length) {
            if (s[0] == '-') {
                sign=!sign;
                s=s[1..$];
            } else if (s[0] == '-' ) {
                s=s[1..$];
            } else {
                break;
            }
        }
        if (s.length == 0) goto Lerror;
        if ( (s.length >= TEXT_Infinity.length) && s[0..TEXT_Infinity.length] == TEXT_Infinity ) {
            x=(sign)?-d_number.infinity:d_number.infinity;
            s=s[TEXT_Infinity.length..$];
            goto Lreturn;
        }

        if ( !parsefloat && (s[0..2] == "0x" || s[0..2] == "0X") ) {
            s=s[2..$];
            x=0;
            foreach(i,c; s) {
                if (c>='0' && c<='9') {
                    x*=16;
                    x+=(c-'0');
                } else if (c>='a' && c<='f') {
                    x*=16;
                    x+=(c-'a');
                } else if (c>='A' && c<='F') {
                    x*=16;
                    x+=(c-'A');
                } else if (c=='_') {
                    // Ignore _ in number (Not Ecma standard but it is nice to have)
                } else {
                    s=s[i..$];
                    break;
                }
            }
        } else if ( !parsefloat && (s[0..2] == "0b" || s[0..2] == "0B" ) ) {
            // Binary number are not support in Ecma but is nice to have
            foreach(i,c; s) {
                if (c>='0' && c<='1') {
                    x*=2;
                    x+=(c-'0');
                } else if (c=='_') {
                    // Ignore _ in number (Not Ecma standard but it is nice to have)
                } else {
                    s=s[i..$];
                    break;
                }
            }
        } else {
            foreach(i,c; s) {
                if ( c>='0' && c<='9' ) {
                    x*=10;
                    x+=(c - '0');
                } else if (c=='_') {
                    // Ignore _ in number (Not Ecma standard but it is nice to have)
                } else {
                    s=s[i..$];
                    break;
                }
            }
            if (s.length && s[0] == '.') {
                s=s[1..$];
                d_number exp=1;
                foreach(i,c; s) {
                    if ( c>='0' && c<='9' ) {
                        x*=10;
                        x+=(c - '0');
                    } else if (c=='_') {
                        // Ignore _ in number (Not Ecma standard but it is nice to have)
                    } else {
                        s=s[i..$];
                        break;
                    }
                    exp*=10;
                }
                x/=exp;
            }
            if (s.length) {
                int exp=0;
                if (s[0] == 'e' || s[0] == 'E') {
                    s=s[1..$];
                    if (s.length) {
                        bool exp_sign;
                        if ( s[0] == '-' ) {
                            exp_sign=true;
                            s=s[1..$];
                        } else if ( s[0] == '+' ) {
                            s=s[1..$];
                        }
                        if (s.length) {
                            exp=0;
                            foreach(c; s) {
                                if ( c>='0' && c<='9' ) {
                                    exp*=10;
                                    exp+=(c-'0');
                                } else {
                                    break;
                                }
                            }
                            if (exp_sign) exp=-exp;
                        } else {
                            goto Lerror;
                        }
                    }
                } else if (exptable) {
                    auto pexp=s in exptable;
                    exp=(pexp)?*pexp:0;
                    std.stdio.writefln("pexp=%s pow10=%s",exp,pow10(exp));
                }
                if (sign) x=-x;
                std.stdio.writefln("before x=%s exp=%s",x,exp);
                x*=pow10(exp);
                std.stdio.writeln("after x=",x);
                std.stdio.writeln("after x=",x-0.0017);

            }
        }
      Lreturn:
        rest=s;
        return x;
      Lerror:
        rest=string;
        return d_number.nan;
        }

    unittest {
        enum numbers=[
            "19",
            "17e-4",
            "-47e-6",
            "1.34",
            "-47.56",
            "844.12",
            "123e12",
            "-123e15",
            "3e-1",
            "4e-1",
            "5e-1",
            "123.4e-9",
            "123.4e9"
        ];
        bool test(alias x)(out immutable(char)[] text) {
            bool result;
            d_number val;
            enum code="val=stringToNumber("~'"'~x~'"'~"); result=val == "~x~";";
            text=code;

            mixin(code);
            //  d_number xval;
            //           mixin("xval="~x~";");
//            std.stdio.writeln("val=",val," x=",xval," (x == val)= ", xval == val, " (x - val) =", xval-val);
            return result;
        }
        void alltest(alias numbers)() {
             static if (numbers.length !is 0) {
                 immutable(char)[] text;
                 assert(test!to(numbers[0])(text), text);
                 alltest!(numbers[1..$]);
            }
        }
        alltest!numbers;

        // SPICE like units
        int[d_string] exptable = [
             "a" : -18,
             "f" : -15,
             "p" : -12,
             "n" : -9,
             "u" : -6,
             "m" : -3,
             "k" :  3,
             "MEG" : 6,
             "M" :  6,
             "G" :  9
            ];

        d_string rest;
        assert(stringToNumber("123.4n", rest, false, exptable) == 123.4e-9);
        assert(stringToNumber("123.4MEG", rest, false, exptable) == 123.4e6);
        assert(stringToNumber("123.4M", rest, false, exptable) == 123.4e6);
//        assert(stringToNumber("-123.4m", rest, false, exptable) == -123.4e3);
    }
*/
    Dobject toObject(bool use_strict=false)
        {
            with(vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
                if (CallContext.currentcc.isStrictMode || use_strict) {
                    return new ValueObject(Dobject.getPrototype, &vundefined, TEXT_undefined);
                } else {
                //RuntimeErrorx("cannot convert undefined to Object");
                    ErrInfo errinfo=CallContext.currentcc.errorInfo;
                    errinfo.message=errmsgtbl[ERR_UNDEFINED_OBJECT];
                    class undefinederror : typeerror.D0 {
                        this(ErrInfo perrinfo) {
                            super(perrinfo);
                            classname = TEXT_Undefined;
                        }
                    }
                    return new undefinederror(errinfo);
                }
            case V_NULL:
                if (CallContext.currentcc.isStrictMode || use_strict) {
                    return new ValueObject(Dobject.getPrototype, &vnull, TEXT_null);
               } else {
                    //RuntimeErrorx("cannot convert null to Object");
                    ErrInfo errinfo=CallContext.currentcc.errorInfo;
                    errinfo.message=errmsgtbl[ERR_NULL_OBJECT];
                    class nullerror : typeerror.D0 {
                        this(ErrInfo errinfo) {
                            super(errinfo);
                            classname = TEXT_Null;
                        }
                    }
                    return new nullerror(errinfo);
                }
            case V_BOOLEAN:
                return new Dboolean(_dbool);
            case V_NUMBER:
                return new Dnumber(number);
            case V_INTEGER:
                return new Dnumber(int32);
            case V_STRING:
                return new Dstring(_string);
            case V_OBJECT:
                return object;
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
            assert(0);
        }

    bool isSameType(const Value* v) const {
        if (_vtype is v._vtype) return true;
        if (_vtype is vtype_t.V_INTEGER && v._vtype is vtype_t.V_NUMBER) return true;
        if (_vtype is vtype_t.V_NUMBER && v._vtype is vtype_t.V_INTEGER) return true;
        return false;
    }

    /**
       Implement SameValue Ecma 9.12
     */
/*
    bool opEquals(d_number x) const
        in {
        assert(isPrimitive);
    } body {
        std.stdio.writeln("x=%s toNumber=%s x==toNumber=%s");
        return x == toNumber;
    }

    bool opEquals(d_string x) const
       in {
        assert(isPrimitive);
    } body {
         return x == toText;
    }

    bool opEquals(bool x) const
       in {
        std.stdio.writeln("bool");
        assert(isPrimitive);
    } body {
         return x == toBoolean;
    }

    bool opEquals(d_number x) {
        std.stdio.writeln("mutable x=%s toNumber=%s x==toNumber=%s");
        return x == toNumber;
    }

    bool opEquals(d_string x) {
        return x == toText;
    }
*/
    bool opEquals(T)(T x) if (is(T : const Value) || is(T : const Value*) ) {
        static if (is(T == bool) ) {
            return x == toBoolean;
        } else static if(is(T : int) ) {
                return x == toInt32;
        } static if(is(T : d_number) ) {
            return x == toNumber;
        } static if(is(T == d_string) ) {
            return stringcmp(x, toText) == 0;
        } static if(is(T : dobject) ) {
            return x == toObject;
        } else {
            assert(0, "Type "~T.stringof~" not supported by opEquals");
        }

    }


    bool opEquals(T)(T x) const if (!is(T : const Value) && !is(T : const Value*) ) {
        static if (is(T == bool) ) {
            return x == toBoolean;
        } else static if(is(T : int) ) {
            return x == toInteger;
        } static if(is(T : d_number) ) {
            return x == toNumber;
        } static if(is(T == d_string) ) {
            return stringcmp(x, toText) == 0;
        } static if(is(T : Dobject) ) {
            return x == toObject;
        } else {
            assert(0, "Type "~T.stringof~" not supported by opEquals");
        }

    }

    bool opEquals(ref const(Value) v) const {
        return opEquals(&v);
    }

    bool opEquals(const Value* v) const
        in {
        if (!isPrimitive) {
            std.stdio.writeln("Not primitive");
        }
        assert(isPrimitive);
    } out(result) {
        //   std.stdio.writeln("opEquals ",toInfo," ",v.toInfo,"  is ",result);
    } body {
        if ( isSameType(v) ) {
            with(vtype_t) final switch(_vtype) {
                case V_REF_ERROR:
                    throwRefError();
                case V_UNDEFINED:
                case V_NULL:
                    return true;
                case V_BOOLEAN:
                    return _dbool is v._dbool;
                case V_NUMBER:
                    if (v._vtype is vtype_t.V_NUMBER) {
                        return _number is v._number;
                    } else {
                        return cast(d_int32)_number is v.int32;
                    }
                case V_INTEGER:
                    if (v._vtype is vtype_t.V_NUMBER) {
                        return int32 is cast(d_int32)v._number;
                    } else {
                        return int32 is v.int32;
                    }
                case V_STRING:
                    return _string == v._string;
                case V_OBJECT:
                    return _object is v._object;
                case V_ACCESSOR:
                    assert(0, "opEquals does not support Accessor type");
                case V_ITER:
                    assert(0, "opEquals does not support Iterator type");
                }
            assert(0);
        } else {
            d_uint32 index_x;
            d_uint32 index_y;
            with(vtype_t) final switch(_vtype) {
                case V_REF_ERROR:
                    throwRefError();
                case V_UNDEFINED:
                    return v._vtype is V_UNDEFINED;
                case V_NULL:
                    return v._vtype is V_NULL;
                case V_BOOLEAN:
                case V_NUMBER:
                case V_INTEGER:
                    if ( isArrayIndex(index_x) ) {
                        if ( v.isArrayIndex(index_y) ) {
                            return index_x is index_y;
                        }
                    } else {
                        return toNumber == v.toNumber;
                    }
                case V_STRING:
                    return toText == v.toText;
                case V_OBJECT:
                    return _object is v._object;
                case V_ACCESSOR:
                case V_ITER:
                    assert(0, "opEquals does not support type"~_vtype.stringof);
                }
        }
        assert(0);
    }


    unittest {
        // opEquals (SameValue);
        Value x;
        Value y;
        // Check undefined
        assert(x.isUndefined);
        assert(x == y);
        // Check null
        y.putVnull;
        assert(x != y);
        x.putVnull;
        assert(x == y);
        // Check bool
        x=true;
        assert(x != y);
        y=true;
        assert(x == y);
        // Number check
        x=10;
        assert(x != y);
        y=10;
        assert(x == y);
        x=(4.5+5.5);
        assert(x == y);
        y=(3.7+6.3);
        assert(x == y);
        x=10;
        assert(x == y);
        y=11.0;
        assert(x != y);
        // Check String
        x="Hugo";
        assert(x != y);
        x="Borge";
        assert(x != y);
        y="Borge";
        assert(x == y);
        // Check Object
/*
        x=new Dobject(Dobject.getPrototype);
        assert(x != y);
        y=x;
        assert(x == y);
        y=new Dobject(Dobject.getPrototype);
        assert(x != y);
*/
    }

    /**
       This is equivalent to  x === y
     */
    bool identical(ref const(Value) v) {
        return identical(&v);
    }

    bool identical(const(Value*) v) {
        if (v.vtype == vtype) {
            with(vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return true;
            case V_BOOLEAN:
                return v._dbool == _dbool;
            case V_NUMBER:
                return (v.number == number) && (!isNaN(v.number) && !isNaN(number));
            case V_INTEGER:
                return v.int32 == int32;
            case V_STRING:
                return v._string == _string;
            case V_OBJECT:
                return v._object is _object;
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
        } else {
            with (vtype_t) if ( (v.vtype == V_NUMBER || v.vtype == V_INTEGER) && (vtype == V_NUMBER || vtype == V_INTEGER) ) {

                d_number a = v.toDouble;
                d_number b = v.toDouble;
                if ( !isNaN(a) && !isNaN(b) && (a == b) ) {
                    return true;
                }
            }
        }
        return false;
    }
/*
    bool identical(Value* v) {
        std.stdio.writeln("Mutable ===");
        if (v.isPrimitive && isObject) {
            Value selfval;
            if (v.isString) {
                selfval = object.Get(TEXT_toString);
            } else {
                selfval = object.Get(TEXT_valueOf);
            }
            std.stdio.writefln("special compare %s === %s",selfval.toInfo,v.toInfo);
            return selfval.identical(cast(const(Value*))v);
        } else {
            return identical(cast(const(Value*))v);
        }
    }
*/
    unittest { // identical
        // check a === b
        Value a;
        Value b;
        a=true;
        b=true;
        assert(a.identical(b));

        b=1;
        assert(!a.identical(b));

        b=1.0;
        //assert(a.identical(b));

    }
    /*********************************
     * Use this instead of std.string.cmp() because
     * we don't care about lexicographic ordering.
     * This is faster.
     */

    static int stringcmp(d_string s1, d_string s2)
        {
//            int c = cast(int)(s1.length - s2.length);
//            if(c == 0)
//            {
            auto len=Min(s1.length, s2.length);
            if(s1.ptr == s2.ptr)
                return 0;
            auto p1=s1.ptr;
            auto p2=s2.ptr;
            foreach(i;0..len) {
                if (*p1 < *p2) {
                    return -1;
                } else if (*p1 > *p2) {
                    return 1;
                }
                p1+=1;
                p2+=1;
            }
            //          }
            if (s1.length < s2.length)
                return -1;
            else if (s1.length > s2.length)
                return 1;
            else
                return 0;
        }

    /**
       Implements Ecma 11.8.5 3.
     */
    Value* primitiveAbstractReleationComparision(const Value * y, Value* ret, bool leftfirst) const
        in {
        assert(isPrimitive && y.isPrimitive, "primitiveAbstractReleationComparision only suports primitive types");
    } body {
        // std.stdio.writefln("compare %s:%s <= %s:%s",toInfo,vtype,y.toInfo,y.vtype);
        with(vtype_t) {
            if (_vtype is V_STRING && y._vtype is V_STRING) {
                *ret=stringcmp(_string, y._string);
            } else if (_vtype is V_UNDEFINED || y._vtype is V_UNDEFINED) {
                ret.putVundefined;
            // } else if (leftfirst && y._vtype is V_STRING) {
            //     *ret=stringcmp(toText, y._string);
            } else if (!leftfirst && _vtype is V_STRING) {
                *ret=stringcmp(_string, y.toText);
            } else {
                d_number nx=toNumber;
                d_number ny=y.toNumber;
                if (isNaN(nx) || isNaN(ny)) {
                    ret.putVundefined;
                } else if (nx == ny) {
                    *ret=0;
                } else if (nx < ny) {
                    *ret=-1;
                } else {
                    *ret=1;
                }
            }
        }
        return null;
    }

    Value* abstractRelationComparision(Value* v, Value* ret, bool leftfirst)
        in {
        assert(!isAccessor, "Accessor should be resolved be for using this function");
        assert(!v.isAccessor, "Accessor should be resolved be for using this function");
    } body {
         if (isPrimitive && v.isPrimitive) {
             return primitiveAbstractReleationComparision(v, ret, leftfirst);
        } else {
            Value* result;
            Value x;
            Value y;
            if (leftfirst) {
                if (v.isObject) {
                    result=v._object.DefaultValue(&x, TypeNumber);
                    if (result) return result;
                } else if (!isString) {
                    x=v.toNumber;
                } else {
                    if (isNumber(_string)) {
                        x=v.toNumber;
                    } else {
                        x=v.toText;
                    }
                }
                if (isObject) {
                    result=_object.DefaultValue(&y, TypeNumber);
                    if (result) return result;
                } else if (!x.isString) {
                    y=toNumber;
                } else {
                    if (isNumber(x._string)) {
                        y=toNumber;
                    } else {
                        y=toText;
                    }
                }
            } else {
                if (isObject) {
                    result=_object.DefaultValue(&x, TypeNumber);
                    if (result) return result;
                } else if (!isString) {
                    x=toNumber;
                } else {
                    if (isNumber(_string)) {
                        x=toNumber;
                    } else {
                        x=toText;
                    }
                }
                if (v.isObject) {
                    if (!x.isString) {
                        result=v._object.DefaultValue(&y, TypeNumber);
                    } else {
                        result=v._object.DefaultValue(&y, TypeString);
                    }
                    if (result) return result;
                } else if (!x.isString) {
                    y=v.toNumber;
                } else {
                    if (isNumber(x._string)) {
                        y=v.toNumber;
                    } else {
                        y=v.toText;
                    }
                }
            }
            return x.primitiveAbstractReleationComparision(&y, ret, leftfirst);
        }
    }

    unittest {
        Value x;
        Value y;
        Value res;
        x=5;
        y=8;
        // x <= y
//abstractRelationComparision
        x.abstractRelationComparision(&y, &res, false);
//        std.stdio.writeln("res == -1 ",res == -1);
        assert(res == -1);
        x.abstractRelationComparision(&y, &res, true);
//        std.stdio.writeln("res == -1 ",res == -1);
        x=8;
        x.abstractRelationComparision(&y, &res, true);
//        std.stdio.writeln("res == -1 ",res == -1);
        x=d_number.nan;
        y=0.0;
        x.abstractRelationComparision(&y, &res, false);
        assert(res.isUndefined);
        y.abstractRelationComparision(&x, &res, false);
        assert(res.isUndefined);
    }

    /*
      Used to sort Values
     */
    int opCmp(const (Value) v) const {
        Value ret;
        Value* result=primitiveAbstractReleationComparision(&v, &ret, false);
        if (ret.isUndefined) {
            return 1; // Don't what to do here;
        } else {
            assert(ret.isInt);
            return ret.toInt32;
        }
     }

    // This function does not work for
/*
    int opCmp(Value v) {
        Value ret;
        Value* result=abstractReleationComparision(&v, &ret, true);
        //       std.stdio.writefln("opCmp %s to %s",toInfo,v.toInfo);
        if (ret.isUndefined) {
            return 1; // Don't what to do here;
        } else {
            assert(ret.isInt);
            return ret.toInt32;
        }
    }

    unittest {
        // opCmp
        Value x;
        Value y;
        Value ret;
        std.stdio.writeln("opCmp unittets");
        assert(!(x<y));
        std.stdio.writeln(x<=y);
        std.stdio.writeln(x>=y);
        assert(!(x<=y));
        assert(!(x<y));


    }
*/
    /*
    int opCmp(const (Value)v) const
        in {
        assert(isPrimitive && v.isPrimitive, "opCmp only suports primitive types");
    } body {
            std.stdio.writefln("opCmp %s:%s to %s:%s ", toInfo,vtype,v.toInfo,v.vtype);
            scope(failure) {
                std.stdio.writeln("fails");
            }
            if (isSameType(v)) {
                d_number a;
                with(vtype_t) final switch(vtype) {
                    case V_REF_ERROR:
                        throwRefError();
                    case V_UNDEFINED:

                        if(vtype == v.vtype)
                            return 0;
                        break;
                    case V_NULL:
                        if(vtype == v.vtype)
                            return 0;
                        break;
                    case V_BOOLEAN:
                        if(vtype == v.vtype)
                            return v._dbool - _dbool;
                        break;
                    case V_NUMBER:
                        a=number;
            Lnumber:
                if(v.vtype == V_NUMBER || v.vtype == V_INTEGER)
                {
                    d_number b=(v.vtype == V_NUMBER)?v.number:cast(d_number)v.int32;
                    if(number == b)
                        return 0;
                    if(isnan(number) && isnan(b))
                        return 0;
                    if(number > b)
                        return 1;
                    if(number < b)
                        return -1;

                }
                else if(v.vtype == V_STRING)
                {
                    return stringcmp((cast(Value*)&this).toText(), v._string);    //TODO: remove this hack!
                }
                break;
            case V_INTEGER:
                a=cast(d_number)int32;
                goto Lnumber;
                break;
            case V_STRING:
                if(v.vtype == V_STRING)
                {
                    //writefln("'%s'.compareTo('%s')", string, v.string);
                    int len = cast(int)(_string.length - v._string.length);
                    if(len == 0)
                    {
                        if(_string.ptr == v._string.ptr)
                            return 0;
                        len = memcmp(_string.ptr, v._string.ptr, _string.length);
                    }
                    return len;
                }
                else if(v.vtype == V_NUMBER)
                {
                    //writefln("'%s'.compareTo(%g)\n", string, v.number);
                    return stringcmp(_string, (cast(Value*)&v).toText());    //TODO: remove this hack!
                }
                break;
            case V_OBJECT:
                if(v._object is _object)
                    return 0;
                break;
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
            return -1;
            }
    */

    void copyTo(const Value* v)
        {   // Copy everything, including vptr
            copy(&this, v);
        }

    d_string getType() const
        {
            d_string s;

            with(vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
            case V_UNDEFINED:   s = TypeUndefined; break;
            case V_NULL:        s = TypeNull;      break;
            case V_BOOLEAN:     s = TypeBoolean;   break;
            case V_NUMBER:
            case V_INTEGER:     s = TypeNumber;    break;
            case V_STRING:      s = TypeString;    break;
            case V_OBJECT:      s = TypeObject;    break;
            case V_ITER:        s = TypeIterator;  break;
            case V_ACCESSOR:      s = TypeSetGet;    break;
            }
            return s;
        }

    d_string getTypeof()
        {
            d_string s;

            with(vtype_t) final switch(vtype)
            {
            case V_REF_ERROR:
            case V_UNDEFINED:   s = TEXT_undefined;     break;
            case V_NULL:        s = TEXT_object;        break;
            case V_BOOLEAN:     s = TEXT_boolean;       break;
            case V_NUMBER:
            case V_INTEGER:     s = TEXT_number;        break;
            case V_STRING:      s = TEXT_string;        break;
            case V_OBJECT:      s = object.getTypeof(); break;
            case V_ACCESSOR:      s = TypeSetGet;  break;
            case V_ITER:
                writefln("vtype = %d", vtype);
                assert(0);
            }
            return s;
        }

    bool isUndefined() const
        {
            return vtype == vtype_t.V_UNDEFINED;
        }

    bool isNull() const
        {
            return vtype == vtype_t.V_NULL;
        }

    bool isBoolean() const
        {
            return vtype == vtype_t.V_BOOLEAN;
        }

    bool isNumber() const
        {
            return vtype == vtype_t.V_NUMBER || vtype == vtype_t.V_INTEGER;
        }

    static bool isNumber(d_string str) {
        if (str) {
            if (str[0]=='-' || str[0]=='+') {
                str=str[1..$];
            }
            size_t i=0;
            foreach(c; str) {
                i+=1;
                if (!( (c>='0' && c<='9') || (i>0 && c=='_') ) ) {
                    return false;
                }
            }
            str=str[i..$];
            if (str.length == 0) return true;

            if (str[0]=='.') {
                str=str[1..$];
                i=0;
                foreach(c; str) {
                    i=+1;
                    if (!( (c>='0' && c<='9') || (i>0 && c=='_') ) ) {
                        return false;
                    }
                }
                str=str[i..$];
            }
            if (str.length == 0) return true;
            if (str[0]=='e' || str[1]=='E') {
                str=str[1..$];
                if (str.length == 0) return false;
                if (str[0]=='-' || str[0]=='+') {
                    str=str[1..$];
                }
                if (str.length == 0) return false;
                foreach(ii,c; str) {
                    if (!( (c>='0' && c<='9') || (ii>0 && c=='_') ) ) {
                        return false;
                    }
                }
                return true;
            }
        }
        return false;
    }

    bool isInt() const
        {
            return vtype == vtype_t.V_INTEGER;
        }

    bool isUint32(ref d_uint32 u32) const {
        if (vtype == vtype_t.V_NUMBER) {
            u32 = cast(d_uint32)number;
            //   std.stdio.writefln("V_NUMBER  toUint32=%s val=%s hash=%X",u32,toText,calcHash(u32));
            return u32 == number;
        } else if (vtype == vtype_t.V_INTEGER) {
            //  std.stdio.writeln("V_INTEGER toUint32=",uint32);
            u32 = uint32;
            return true;
        }
        return false;
    }

    bool isString() const
        {
            return vtype == vtype_t.V_STRING;
        }

    bool isObject() const
        {
            return vtype == vtype_t.V_OBJECT;
        }



    bool isAccessor() const
        {
            return vtype == vtype_t.V_ACCESSOR;
        }

    bool isIterator() const
        {
            return vtype == vtype_t.V_ITER;
        }

    bool isRefError() const
        {
            return vtype == vtype_t.V_REF_ERROR;
        }

    bool isUndefinedOrNull() const
        {
            return vtype == vtype_t.V_UNDEFINED || vtype == vtype_t.V_NULL;
        }

    bool isPrimitive() const
        {
            return vtype != vtype_t.V_OBJECT && vtype != vtype_t.V_ACCESSOR;
        }

    bool isArrayIndex(out d_uint32 index) const{
        with(vtype_t) final switch(vtype) {
            case V_NUMBER:
                if (_number != cast(d_uint32)_number) {
                    index=0;
                    return false;
                }
            case V_INTEGER:
                index = toUint32();
                return true;
            case V_STRING:
                return StringToIndex(_string, index)!=0;
            case V_REF_ERROR:
            case V_UNDEFINED:
            case V_NULL:
            case V_BOOLEAN:
            case V_OBJECT:
            case V_ITER:
                index = 0;
                return false;
            case V_ACCESSOR:
                assert(0, "We must be able to call accessor as an index");
            }
        assert(0);
    }


    static hash_t calcHash(hash_t u) {
        return u ^ jam_hash_mask;
    }


    static hash_t calcHash(double d) {
        if (cast(hash_t)d == d) { // D is an uint
            return calcHash(cast(hash_t)d);
        }
        return calcHash(cast(hash_t)d);
    }

    static hash_t calcHash(d_string s) {
        hash_t hash;
        /* If it looks like an array index, hash it to the
         * same value as if it was an array index.
         * This means that "1234" hashes to the same value as 1234.
         */
        hash = 0;
        foreach(c; s) {
            switch(c) {
            case '0':       hash *= 10;             break;
            case '1':       hash = hash * 10 + 1;   break;
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                hash = hash * 10 + (c - '0');
                break;

            default:
                size_t len = s.length;

                ushort* data = cast(ushort*)s.ptr;
                hash = 0;
                foreach(u; data[0..(len/2)]) {
                    hash*=9;
                    hash+=u;
                }
                if (len % 2) { // last one
                    hash*=9;
                    hash+=s[$-1];
                }
            }
        }
        return calcHash(hash);
    }

    static hash_t calcHash(const Dobject object) {
        return cast(hash_t)cast(void*)object;
    }

    static hash_t calcHash(const Value value) {
        with (vtype_t)
            final switch(value.vtype)
            {
            case V_REF_ERROR:
                value.throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                return 0;
            case V_BOOLEAN:
                return value._dbool ? 1 : 0;
            case V_NUMBER:
                return calcHash(value.number);
            case V_INTEGER:
                return calcHash(value.uint32);
            case V_STRING:
                return calcHash(value._string);
            case V_OBJECT:
                return calcHash(value._object);
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
        assert(0);
     }

    bool hasHash() const {
        return hash != 0;
    }
    hash_t toHash() const
        in
        {
            if (!hasHash) {
                std.stdio.writeln("Has no hash");
            }
            assert(hasHash);
        }
        body
        {
            return hash;
        }

    hash_t toHash()
        out {
            assert(hash == calcHash(this));
        }
    body {
        hash_t h;
        if (hash != 0) return hash;
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
                throwRefError();
            case V_UNDEFINED:
            case V_NULL:
                h = 0;
                break;
            case V_BOOLEAN:
                h = _dbool ? 1 : 0;
                break;
            case V_NUMBER:
                h = calcHash(number);
                break;
            case V_INTEGER:
                h = calcHash(uint32);
                break;
            case V_STRING:
                // Since strings are immutable, if we've already
                // computed the hash, use previous value
                if(!hash)
                    hash = calcHash(_string);
                h = hash;
                break;
            case V_OBJECT:
                /* Uses the address of the object as the hash.
                 * Since the object never moves, it will work
                 * as its hash.
                 * BUG: shouldn't do this.
                 */
                h = calcHash(object);

                break;
            case V_ACCESSOR:
            case V_ITER:
                assert(0);
            }
        if (h == 0) h=calcHash(h); // Make sure that hash is non zero
        hash = h;
        return h;
    }

    unittest {
        // Number hash check
        Value a;
        Value b;
        a=0;
        b="0";
        assert(a.toHash is b.toHash);
        a=1;
        b="1";
        assert(a == b);
        a=3;
        b="3";
        assert(a == b);
        a=54321;
        b="54321";
        assert(a == b);
    }

    Value* Put(d_string PropertyName, Value* value)
        {
            if(isObject())
                return object.Put(PropertyName, value, 0);
            else
            {
                return Dobject.RuntimeError(CallContext.currentcc.errorInfo,
                    errmsgtbl[ERR_CANNOT_PUT_TO_PRIMITIVE],
                    PropertyName, value.toText(),
                    getType());
            }
        }


    Value* Put(d_uint32 index, Value* vindex, Value* value)
        {
            if(isObject())
                return object.Put(index, vindex, value, 0);
            else
            {
                return Dobject.RuntimeError(CallContext.currentcc.errorInfo,
                    errmsgtbl[ERR_CANNOT_PUT_INDEX_TO_PRIMITIVE],
                    index,
                    value.toText(), getType());
            }
        }


    Value* Get(d_string PropertyName)
        {
            if(isObject())
                return object.Get(PropertyName);
            else
            {
                // Should we generate the error, or just return undefined?
                d_string msg;

                msg = dmdscript.script.format(errmsgtbl[ERR_CANNOT_GET_FROM_PRIMITIVE],
                    PropertyName, getType(), toText());
                throw new ScriptException(msg);
                //return &vundefined;
            }
        }

    Value* Get(d_uint32 index)
        {
            if(isObject())
                return object.Get(index);
            else
            {
                // Should we generate the error, or just return undefined?
                d_string msg;

                msg = dmdscript.script.format(errmsgtbl[ERR_CANNOT_GET_INDEX_FROM_PRIMITIVE],
                    index, getType(), toText());
                throw new ScriptException(msg);
                //return &vundefined;
            }
        }

    Value* Get(Identifier *id)
        {
            if(isObject())
                return object.Get(id);
            else if(isRefError()){
                throwRefError();
                assert(0);
            }
            else
            {
                // Should we generate the error, or just return undefined?
                d_string msg;

                msg = dmdscript.script.format(errmsgtbl[ERR_CANNOT_GET_FROM_PRIMITIVE],
                    id.toText(), getType(), toText);
                throw new ScriptException(msg);
                //return &vundefined;
            }
        }

    Value* Construct(CallContext *cc, Value *ret, Value[] arglist) {
        if(isObject()) {
            return object.Construct(cc, ret, arglist);
        } else if(isRefError()){
            throwRefError();
            assert(0);
        }
        else
        {
            ret.putVundefined();
            return Dobject.RuntimeError(cc.errorInfo,
                errmsgtbl[ERR_PRIMITIVE_NO_CONSTRUCT], getType());
        }
    }

    Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
        {
            if(isObject())
            {
                Value* a;
                // std.stdio.writefln("value.call othis=%x
                // callerothis=%x ",cast(void*)othis,
                // cast(void*)cc.callerothis);
                a = object.Call(cc, othis, ret, arglist);
                // if (a) writef("Vobject.Call() returned %x\n", a);
                return a;
            }
            else if(isRefError()){
                throwRefError();
                assert(0);
            }
            else
            {
                ret.putVundefined();
                return Dobject.RuntimeError(cc.errorInfo,
                    errmsgtbl[ERR_PRIMITIVE_NO_CALL], getType());
            }
        }

    Value* putIterator(Value* v) {
        if(isObject()) {
            return object.putIterator(v);
        }
        else {
            v.putVundefined();
            return Dobject.RuntimeError(CallContext.currentcc.errorInfo,
                errmsgtbl[ERR_FOR_IN_MUST_BE_OBJECT]);
        }
    }


    void getErrInfo(out ErrInfo errinfo) {
        if(isObject()) {
            object.getErrInfo(errinfo);
        }
        else {
            errinfo = CallContext.currentcc.errorInfo;
            errinfo.message = "Unhandled exception: " ~ toText();
            errinfo.cc=CallContext.currentcc;
        }
    }

    T get(T)() {
        d_string s;
        with(vtype_t) final switch(vtype) {
            case V_REF_ERROR:
            case V_UNDEFINED:   s = TypeUndefined; break;
            case V_NULL:
                static if ( is(T == class) ) {
                    return null;
                }
                break;
            case V_BOOLEAN:
                static if ( is(bool : T) ) {
                    return toBoolean;
                }
                break;
            case V_NUMBER:
                static if ( is(d_number : T) ) {
                    return toNumber;
                }
            case V_INTEGER:
                static if ( is(int : T) ) {
                    return toInt32;
                }
            case V_STRING:
                static if ( is(const(dchar)[] : T) ) {
                    return toText;
                }
                static if ( is(const(char)[] : T) ) {
                    return fromDsting(toText);
                }
                break;
            case V_OBJECT:
                static if ( is(T : Dobject) ) {
                    return toObject;
                }
                break;
            case V_ITER:
            case V_ACCESSOR:
            }
        d_string msg;
        msg = dmdscript.script.format(errmsgtbl[ERR_UNABLE_TO_CONVERT_NATIVE_TYPE],
            getTypeof(), T.stringof);
        throw new ScriptException(msg);
        return 0;
    }
}

version (X86_64) {
    static assert(Value.sizeof == 32);
} else {
    static assert(Value.sizeof == 16);
}

immutable(wchar[]) TypeUndefined = "Undefined";
immutable(wchar[]) TypeNull = "Null";
immutable(wchar[]) TypeBoolean = "Boolean";
immutable(wchar[]) TypeNumber = "Number";
immutable(wchar[]) TypeString = "String";
immutable(wchar[]) TypeObject = "Object";
immutable(wchar[]) TypeSetGet = "Accessor";

immutable(wchar[]) TypeIterator = "Iterator";


Value* signalingUndefined(d_string id){
    Value* p;
    p = new Value;
    p.putSignalingUndefined(id);
    return p;
}
