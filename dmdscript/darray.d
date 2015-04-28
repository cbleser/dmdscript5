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
 * Upgrading to EcmaScript 5.1 by Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */


module dmdscript.darray;

//Nonstandard treatment of Infinity as array length in slice/splice functions, supported by majority of browsers
//also treats negative starting index in splice wrapping it around just like in slice
version =  SliceSpliceExtension;

import std.string;
import std.c.stdlib;
import std.math;

import dmdscript.script;
import dmdscript.value;
import dmdscript.dobject;
import dmdscript.threadcontext;
import dmdscript.identifier;
import dmdscript.dfunction;
import dmdscript.text;
import dmdscript.property;
import dmdscript.errmsgs;
import dmdscript.dnative;
import dmdscript.program;

/* ===================== Darray_constructor ==================== */

class DarrayConstructor : Dfunction
{
    this()
    {
        super(1, Dfunction_prototype);
        name = "Array";
    }

    override Value* Construct(CallContext *cc, Value *ret, Value[] arglist)
    {
        // ECMA 15.4.2
        Darray a;

        a = new Darray();
        if(arglist.length == 0)
        {
            a._ulength = 0;
        }
        else if(arglist.length == 1)
        {
            Value* v = &arglist[0];

            if(v.isNumber())
            {
                d_uint32 len;

                len = v.toUint32();
                if(cast(double)len != v.number)
                {
                    ret.putVundefined();
                    return RangeError(cc.errorInfo, ERR_ARRAY_LEN_OUT_OF_BOUNDS, v.number);
                }
                else
                {
                    a._ulength = len;
                }
            }
            else
            {
                a._ulength = 1;
                a.Put(cast(d_uint32)0, v, 0, true);
            }
        }
        else
        {
            //if (arglist.length > 10) writef("Array constructor: arglist.length = %d\n", arglist.length);
            a._ulength = cast(uint)arglist.length; // 64bit cast
            for(uint k = 0; k < arglist.length; k++)
            {
                a.Put(k, &arglist[k], 0, true);
            }
        }
        Value.copy(ret, &a.value);
        //writef("Darray_constructor.Construct(): length = %g\n", a.length.number);
        return null;
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        // ECMA 15.4.1
        return Construct(cc, ret, arglist);
    }
}


/* ===================== Darray_prototype_toString ================= */

Value* Darray_prototype_toString(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // writef("Darray_prototype_toString()\n");
    Value* result;
    if (othis.isDarray) {
        result=array_join(othis, ret, null);
    } else {
        result=Dobject.RuntimeError(cc.errorInfo, ERR_ARRAY_EXPECTED);
    }
    return result;
}

/* ===================== Darray_prototype_toLocaleString ================= */

Value* Darray_prototype_toLocaleString(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.4.4.3
    d_string separator;
    d_string r;
    d_uint32 len;
    d_uint32 k;
    Value* v;

    //writef("array_join(othis = %p)\n", othis);

    if(!othis.isClass(TEXT_Array))
    {
        ret.putVundefined();
        return Dobject.RuntimeError(cc.errorInfo, ERR_TLS_NOT_TRANSFERRABLE);
    }

    v = othis.Get(TEXT_length);
    len = v ? v.toUint32() : 0;

    Program prog = cc.prog;
    if(!prog.slist)
    {
        // Determine what list separator is only once per thread
        //prog.slist = list_separator(prog.lcid);
        prog.slist = ",";
    }
    separator = prog.slist;

    for(k = 0; k != len; k++)
    {
        if(k)
            r ~= separator;
        v = othis.Get(k);
        if(v && !v.isUndefinedOrNull())
        {
            Dobject ot;

            ot = v.toObject();
            v = ot.Get(TEXT_toLocaleString);
            if(v && !v.isPrimitive())   // if it's an Object
            {
                Value* a;
                Dobject o;
                Value rt;

                o = v.object;
                rt.putVundefined();
                a = o.Call(cc, ot, &rt, null);
                if(a)                   // if exception was thrown
                    return a;
                r ~= rt.toText();
            }
        }
    }

    ret.putVstring(r);
    return null;
}

/* ===================== Darray_prototype_concat ================= */

Value* Darray_prototype_concat(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    CallContext.currentcc=cc;
    // ECMA v3 15.4.4.4
    Darray A;
    Darray E;
    Value* v;
    d_uint32 k;
    d_uint32 n;
    d_uint32 a;

    A = new Darray();
    n = 0;
    v = &othis.value;
    for(a = 0;; a++)
    {
        if(!v.isPrimitive() && v.object.isDarray())
        {
            d_uint32 len;

            E = cast(Darray)v.object;
            len = E.ulength;
            for(k = 0; k != len; k++)
            {
                v = E.Get(k);
                if(v)
                    A.Put(n, v, 0, true);
                n++;
            }
        }
        else
        {
            A.Put(n, v, 0, true);
            n++;
        }
        if(a == arglist.length)
            break;
        v = &arglist[a];
    }

    A.Put(TEXT_length, n, 0);
    Value.copy(ret, &A.value);
    return null;
}

/* ===================== Darray_prototype_join ================= */

Value* Darray_prototype_join(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return array_join(othis, ret, arglist);
}

Value* array_join(Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.4.4.3
    d_string separator;
    d_string r;
    d_uint32 len;
    d_uint32 k;
    Value* v;

    //writef("array_join(othis = %p)\n", othis);
    v = othis.Get(TEXT_length);
    len = v ? v.toUint32() : 0;
    if(arglist.length == 0 || arglist[0].isUndefined())
        separator = TEXT_comma;
    else
        separator = arglist[0].toText();

    if (len > Dobject.iteration_limit) {
        ret.putVundefined;
        return Dobject.RuntimeError(CallContext.currentcc.errorInfo, ERR_ITERATION_LIMIT);
    }
    for(k = 0; k != len; k++)
    {
        if(k)
            r ~= separator;
        v = othis.Get(k);
        if(v && !v.isUndefinedOrNull())
            r ~= v.toText();
    }

    ret.putVstring(r);
    return null;
}

/* ===================== Darray_prototype_toSource ================= */

Value* Darray_prototype_toSource(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    d_string separator;
    d_string r;
    d_uint32 len;
    d_uint32 k;
    Value* v;

    v = othis.Get(TEXT_length);
    len = v ? v.toUint32() : 0;
    separator = ",";

    r = "["w.idup;
    for(k = 0; k != len; k++)
    {
        if(k)
            r ~= separator;
        v = othis.Get(k);
        if(v && !v.isUndefinedOrNull())
            r ~= v.toSource(othis);
    }
    r ~= "]";

    ret.putVstring(r);
    return null;
}


/* ===================== Darray_prototype_pop ================= */

Value* Darray_prototype_pop(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    CallContext.currentcc=cc;
    // ECMA v3 15.4.4.6
    Value* v;
    d_uint32 u;

    // If othis is a Darray, then we can optimize this significantly
    v = othis.Get(TEXT_length);
    if(!v) {
        v.putVundefined;
    }
    u = v.toUint32();
    if(u == 0) {
        othis[TEXT_length]=0;
        ret.putVundefined();
    }
    else {
        v = othis.Get(u - 1);
        if(!v) {
            v.putVundefined;
        }
        Value.copy(ret, v);
        othis.Delete(u - 1);
        othis[TEXT_length]=u - 1;
    }
    return null;
}

/* ===================== Darray_prototype_push ================= */

Value* Darray_prototype_push(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.4.4.7
    Value* v;
    Value* result;
    d_uint32 a;
    d_uint32 l;

    d_number len;
    // If othis is a Darray, then we can optimize this significantly
    v = othis.Get(TEXT_length);
    if(!v) {
        v.putVundefined;
    }
    len = v.toNumber;

    if ( len == d_number.nan || len == d_number.infinity || len == -d_number.infinity ) {
        l = 0;
        len = 0.0;
    } else if ( len > d_uint32.max ) {
        l = 0; //d_uint32.max;
        len = 0.0;
    } else if ( len < 0 ) {
        l = 0;
        len = d_uint32.max;
    } else {
        l = v.toUint32;
        len = l;
    }

    Darray array;
    if ( othis.isDarray ) {
        array=cast(Darray)othis;
        assert(array);
        for(a = 0; a < arglist.length; a++)
        {
            array.Put(l, &arglist[a], 0);
            if ( l == d_uint32.max ) {
                result=Dobject.RangeError(cc.errorInfo, ERR_ARRAY_LEN_OUT_OF_BOUNDS, l);
                break;
            }
            l++;
        }

    } else {
        for(a = 0; a < arglist.length; a++)
        {
            if ( len <= d_uint32.max ) {
                othis.Put(cast(d_uint32)len, &arglist[a], 0, true);
            } else {
                Value val;
                val=len;
                othis.Put(val.toText, &arglist[a], 0, true);
            }
            len=len+1;
        }
        l=cast(d_uint32)len;
    }

    if ( len > d_uint32.max ) {
        std.stdio.writeln("We need to do something here for dobject");
        othis[TEXT_length]=len;
        ret.putVnumber(len);
    } else {
        //x  Darray array=cast(Darray)othis;
        if (!array) {
            // array.ulength=l;
            //  } else {
            othis[TEXT_length]=l;
        }
        ret.putVnumber(l);

    }
    // }
    return result;
}

/* ===================== Darray_prototype_reverse ================= */

Value* Darray_prototype_reverse(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.4.4.4
    d_uint32 a;
    d_uint32 b;
    Value* va;
    Value* vb;
    Value* v;
    d_uint32 pivot;
    d_uint32 len;
    Value tmp;

    v = othis.Get(TEXT_length);
    len = v ? v.toUint32() : 0;
    pivot = len / 2;
    for(a = 0; a != pivot; a++)
    {
        b = len - a - 1;
        //writef("a = %d, b = %d\n", a, b);
        va = othis.Get(a);
        if(va) {
            Value.copy(&tmp, va);
        }
        vb = othis.Get(b);
        if(vb) {
            othis.Put(a, vb, 0, true);
        }
        else {
            othis.Delete(a);
        }
        if(va) {
            othis.Put(b, &tmp, 0, true);
        }
        else {
            othis.Delete(b);
        }
    }
    Value.copy(ret, &othis.value);
    return null;
}

/* ===================== Darray_prototype_shift ================= */

Value* Darray_prototype_shift(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.4.4.9
    Value* v;
    Value* result;
    d_uint32 len;
    d_uint32 k;

    // If othis is a Darray, then we can optimize this significantly
    //writef("shift(othis = %p)\n", othis);
    v = othis.Get(TEXT_length);
    if(!v) {
        v = &Value.vundefined;
    }
    len = v.toUint32();

    if(len)
    {
        result = othis.Get(0u);
        Value.copy(ret, result ? result : &Value.vundefined);
        for(k = 1; k != len; k++)
        {
            v = othis.Get(k);
            if(v)
            {
                othis.Put(k - 1, v, 0, true);
            }
            else
            {
                othis.Delete(k - 1);
            }
        }
        othis.Delete(len - 1);
        len--;
    }
    else {
        Value.copy(ret, &Value.vundefined);
    }

    othis.Put(TEXT_length, len, DontEnum, true);
    return null;
}


/* ===================== Darray_prototype_slice ================= */

Value* Darray_prototype_slice(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.4.4.10
    d_uint32 len;
    d_uint32 n;
    d_uint32 k;
    d_uint32 r8;

    Value* v;
    Darray A;

    v = othis.Get(TEXT_length);
    if(!v) {
        v = &Value.vundefined;
    }
    len = v.toUint32();

    version(SliceSpliceExtension){
        d_number start;
        d_number end;
        switch(arglist.length) {
        case 0:
            start = Value.vundefined.toNumber();
            end = len;
            break;

        case 1:
            start = arglist[0].toNumber();
            end = len;
            break;

        default:
            start = arglist[0].toNumber();
            if(arglist[1].isUndefined())
                end = len;
            else{
                end = arglist[1].toNumber();
            }
            break;
        }
        if(start < 0) {
            k = cast(uint)(len + start);
            if(cast(d_int32)k < 0)
                k = 0;
        }
        else if(start == d_number.infinity) {
            k = len;
        }
        else if(start == -d_number.infinity) {
            k = 0;
        }
        else {
            k = cast(uint)start;
            if(len < k) {
                k = len;
            }
        }

        if(end < 0) {
            r8 = cast(uint)(len + end);
            if(cast(d_int32)r8 < 0)
                r8 = 0;
        }
        else if(end == d_number.infinity) {
            r8 = len;
        }
        else if(end == -d_number.infinity) {
            r8 = 0;
        }
        else {
            r8 = cast(uint)end;
            if(len < end) {
                r8 = len;
            }
        }
    }
    else {//Canonical ECMA all kinds of infinity maped to 0
        int start;
        int end;
        switch(arglist.length) {
        case 0:
            start = Value.vundefined.toInt32();
            end = len;
            break;

        case 1:
            start = arglist[0].toInt32();
            end = len;
            break;

        default:
            start = arglist[0].toInt32();
            if(arglist[1].isUndefined()) {
                end = len;
            }
            else {
                end = arglist[1].toInt32();
            }
            break;
        }
        if(start < 0) {
            k = cast(uint)(len + start);
            if(cast(d_int32)k < 0) {
                k = 0;
            }
        }
        else {
            k = cast(uint)start;
            if(len < k) {
                k = len;
            }
        }

        if(end < 0) {
            r8 = cast(uint)(len + end);
            if(cast(d_int32)r8 < 0) {
                r8 = 0;
            }
        }
        else {
            r8 = cast(uint)end;
            if(len < end) {
                r8 = len;
            }
        }
    }
    A = new Darray();
    for(n = 0; k < r8; k++) {
        v = othis.Get(k);
        if (v) {
            A.Put(n, v, 0);
        }
        n++;
    }

    A.Put(TEXT_length, n, 0);
    Value.copy(ret, &A.value);
    return null;
}

/* ===================== Darray_prototype_sort ================= */

static Dobject comparefn;
static CallContext *comparecc;


/**
 Description: vx < vy */
bool compare_value(Value vx, Value vy)
{
    // Value* vx = cast(Value*)x;
    // Value* vy = cast(Value*)y;
    d_string sx;
    d_string sy;
    bool cmp;

    //writef("compare_value()\n");
    if(vx.isUndefined())
    {
        cmp = false;
    }
    else if(vy.isUndefined())
        cmp = !vx.isUndefined;
    else
    {
        if(comparefn)
        {
            Value arglist[2];
            Value ret;
            Value* v;
            d_number n;

            Value.copy(&arglist[0], &vx);
            Value.copy(&arglist[1], &vy);
            ret.putVundefined();
            Value* resp=comparefn.Call(comparecc, comparefn, &ret, arglist);
            if (resp !is null) {
                throw new ErrorValue(resp);
            }
            n = ret.toNumber();
            if(n < 0)
                cmp = true;
            }
        else
        {
            sx = vx.toText();
            sy = vy.toText();
            auto cmpi = std.string.cmp(sx, sy);
            if(cmpi < 0)
                cmp = true;
        }
    }
    return cmp;
}

unittest {
    Value a, b;
    a="a"; b="b";
    assert(compare_value(a,b));
    assert(!compare_value(b,a));
    assert(!compare_value(a,a));
    b.putVundefined;
    assert(compare_value(a,b));
    // std.stdio.writeln(!compare_value(a,b));
    //assert(!compare_value(a,b));
    a.putVundefined;
    assert(!compare_value(a,b));
}

Value* Darray_prototype_sort(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.4.4.11
    Value* v;
    d_uint32 len;
    uint u;
    bool ignoresort;
    v = othis.Get(TEXT_length);
    if (v !is null) {
        if ( v.toInteger < 0 ) {
            ignoresort=true;;
            len = cast(uint)(-v.toInt32()) ;
        } else {
            len = v.toUint32() ;
        }
    }

    if ( !othis.isDarray ) {
        len = othis.lengthAll;
    }

    // This is not optimal, as isArrayIndex is done at least twice
    // for every array member. Additionally, the qsort() by index
    // can be avoided if we can deduce it is not a sparse array.

    Property *p;
    Value[] pvalues;
    d_uint32[] pindices;
    d_uint32 parraydim;
    d_uint32 nprops;

    // First, size & alloc our temp array
    if(len < 100)
    {   // Probably not too sparse an array
        parraydim = len;
    }
    else
    {
        parraydim = 0;
        foreach(ref Property p; othis)
        {
            if(p.attributes == 0)       // don't count special properties
                parraydim++;
        }
        if(parraydim > len)             // could theoretically happen
            parraydim = len;
    }

    Value[] p1 = null;
    Value* v1;
    version(Win32)      // eh and alloca() not working under linux
    {
        if(parraydim < 128)
            v1 = cast(Value*)alloca(parraydim * Value.sizeof);
    }
    if(v1)
        pvalues = v1[0 .. parraydim];
    else
    {
        p1 = new Value[parraydim];
        pvalues = p1;
    }

    d_uint32[] p2 = null;
    d_uint32* p3;
    version(Win32)
    {
        if(parraydim < 128)
            p3 = cast(d_uint32*)alloca(parraydim * d_uint32.sizeof);
    }
    if(p3) {
        pindices = p3[0 .. parraydim];
    }
    else
    {
        p2 = new d_uint32[parraydim];
        pindices = p2;
    }

     // Now fill it with all the Property's that are array indices
    nprops = 0;
    foreach(Value key, ref Property p; othis)
    {
        d_uint32 index;
        if(p.attributes == 0 && key.isArrayIndex(index))
        {
            pindices[nprops] = index;
            Value.copy(&pvalues[nprops], &p.value);
            nprops++;
        }
    }

    synchronized
    {
        comparefn = null;
        comparecc = cc;

        if(arglist.length)
        {
            if(!arglist[0].isPrimitive()) {
                comparefn = arglist[0].object;
            }
        }

        // Sort pvalues[]
//        comparecc.isolated=true; // Scope is isolated in strict mode
                                 // (this === undefined)
        if (!ignoresort) {
            std.algorithm.sort!(compare_value,std.algorithm.SwapStrategy.unstable)(pvalues);
        }
//        comparecc.isolated=false;

//            std.c.stdlib.qsort(pvalues.ptr, nprops, Value.sizeof, &compare_value);


        comparefn = null;
        comparecc = null;
    }

    // Stuff the sorted value's back into the array
    for(u = 0; u < nprops; u++)
    {
        d_uint32 index;

        othis.Put(u, &pvalues[u], 0, true);
        index = pindices[u];
        if(index >= nprops)
        {
            othis.Delete(index);
        }
    }

    delete p1;
    delete p2;

    ret.putVobject(othis);
    return null;
}

/* ===================== Darray_prototype_splice ================= */

Value* Darray_prototype_splice(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.4.4.12
    d_uint32 len;
    d_uint32 k;

    Value* v;
    Darray A;
    d_uint32 a;
    d_uint32 delcnt;
    d_uint32 inscnt;
    d_uint32 startidx;

    v = othis.Get(TEXT_length);
    if(!v)
        v = &Value.vundefined;
    len = v.toUint32();

    version(SliceSpliceExtension){
        d_number start;
        d_number deleteCount;

        switch(arglist.length) {
        case 0:
            start = Value.vundefined.toNumber();
            deleteCount = 0;
            break;

        case 1:
            start = arglist[0].toNumber();
            deleteCount = Value.vundefined.toNumber();
            break;

        default:
            start = arglist[0].toNumber();
            deleteCount = arglist[1].toNumber();
            //checked later
            break;
        }
        if(start == d_number.infinity)
            startidx = len;
        else if(start == -d_number.infinity)
            startidx = 0;
        else{
            if(start < 0) {
                startidx = cast(uint)(len + start);
                if(cast(d_int32)startidx < 0)
                    startidx = 0;
            }
            else {
                startidx = cast(uint)start;
            }
        }
        startidx = startidx > len ? len : startidx;
        if (deleteCount == d_number.infinity) {
            delcnt = len;
        }
        else if (deleteCount == -d_number.infinity) {
            delcnt = 0;
        }
        else {
            delcnt = (cast(int)deleteCount > 0) ? cast(int) deleteCount : 0;
        }
        if(delcnt > len - startidx) {
            delcnt = len - startidx;
        }
    }else{
        long start;
        d_int32 deleteCount;
        switch(arglist.length) {
        case 0:
            start = Value.vundefined.toInt32();
            deleteCount = 0;
            break;

        case 1:
            start = arglist[0].toInt32();
            deleteCount = Value.vundefined.toInt32();
            break;

        default:
            start = arglist[0].toInt32();
            deleteCount = arglist[1].toInt32();
            //checked later
            break;
        }
        startidx = cast(uint)start;
	startidx = startidx > len ? len : startidx;
        delcnt = (deleteCount > 0) ? deleteCount : 0;
        if (delcnt > len - startidx) {
            delcnt = len - startidx;
        }
    }
    A = new Darray();

    // If deleteCount is not specified, ECMA implies it should
    // be 0, while "JavaScript The Definitive Guide" says it should
    // be delete to end of array. Jscript doesn't implement splice().
    // We'll do it the Guide way.
    if(arglist.length < 2)
        delcnt = len - startidx;

    //writef("Darray.splice(startidx = %d, delcnt = %d)\n", startidx, delcnt);
    for(k = 0; k != delcnt; k++) {
        v = othis.Get(startidx + k);
        if(v)
            A.Put(k, v, 0, true);
    }

    A.Put(TEXT_length, delcnt, DontEnum);
    inscnt = cast(d_uint32) ((arglist.length > 2) ? arglist.length - 2 : 0); // 64bit cast
    if(inscnt != delcnt)
    {
        if(inscnt <= delcnt)
        {
            for(k = startidx; k != (len - delcnt); k++)
            {
                v = othis.Get(k + delcnt);
                if(v)
                    othis.Put(k + inscnt, v, 0, true);
                else
                    othis.Delete(k + inscnt);
            }

            for(k = len; k != (len - delcnt + inscnt); k--)
                othis.Delete(k - 1);
        }
        else {
            for(k = len - delcnt; k != startidx; k--)
            {
                v = othis.Get(k + delcnt - 1);
                if(v)
                    othis.Put(k + inscnt - 1, v, 0, true);
                else
                    othis.Delete(k + inscnt - 1);
            }
        }
    }
    k = startidx;
    for(a = 2; a < arglist.length; a++) {
        v = &arglist[a];
        othis.Put(k, v, 0, true);
        k++;
    }

    othis.Put(TEXT_length, len - delcnt + inscnt,  DontEnum);
    Value.copy(ret, &A.value);
    return null;
}

/* ===================== Darray_prototype_unshift ================= */

Value* Darray_prototype_unshift(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist) {
    // ECMA v3 15.4.4.13
    Value* v;
    d_uint32 len;
    d_uint32 k;

    v = othis.Get(TEXT_length);
    if(!v) {
        v = &Value.vundefined;
    }
    len = v.toUint32();

    for(k = len; k>0; k--)
    {
        v = othis.Get(k - 1);
        if (v) {
            othis.Put(k + cast(uint)arglist.length - 1, v, 0);
        }
        else {
            othis.Delete(k + cast(uint)arglist.length - 1);
        }
    }

    for(k = 0; k < arglist.length; k++)
    {
        othis.Put(k, &arglist[k], 0, true);
    }
    othis.Put(TEXT_length, len + arglist.length,  DontEnum, true);
    ret.putVnumber(len + arglist.length);
    return null;
}

/* ===================== Darray_prototype_forEach ================= */

Value* Darray_prototype_forEach(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist) {
    // ECMA v3 15.4.4.13
    Value* v;
    d_uint32 len;
    d_uint32 k;

    v = othis.Get(TEXT_length);
    if(!v)
        v = &Value.vundefined;
    len =(v.toNumber>=0)? v.toUint32(): 0;

    Dobject forEachfn = null;
    CallContext* forEachcc = cc;
    Dobject scopefn;

    if (arglist.length >= 2) {
        if(!arglist[1].isPrimitive()) {
            scopefn = arglist[1].object;
        }
    }

    if (arglist.length >= 1) {
        if(!arglist[0].isPrimitive()) {
            forEachfn = arglist[0].object;
         }
    }

    // forEachcc.isolated=(scopefn is null); // Scope is isolated in
                                          // strict mode
    if (scopefn is null) {
        scopefn = forEachfn;
    }
    // for(k = len; k>0; k--)
    auto args=new Value[3];
    args[2]=othis;
    for (k=0;k<len;k++) {
        v = othis.Get(k);
        if ( v !is null ) {
            args[0]=v;
            args[1]=k;
            Value* resp=forEachfn.Call(forEachcc, scopefn, ret, args);
            if (resp !is null) {
                return resp;
            }
        }
    }
    //   forEachcc.isolated=false;
    forEachfn = null;
    forEachcc = null;

    ret.putVundefined;
    return null;
}

/* ===================== Darray_prototype_reduce ================= */

Value* Darray_prototype_reduce(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist) {
    // ECMA v3 15.4.4.13
    Value* v;
    d_uint32 len;
    d_uint32 k;
    Value previous;

    v = othis.Get(TEXT_length);
    if(!v)
        v = &Value.vundefined;
    len =(v.toNumber>=0)? v.toUint32(): 0;

    Dobject forEachfn = null;
    // CallContext* forEachcc = cc;
    // Dobject scopefn;

    if (arglist.length >= 2) {
        if(!arglist[1].isPrimitive()) {
            previous = arglist[1];
        }
    }

    if (arglist.length >= 1) {
        if(arglist[0].isObject) {
            forEachfn = arglist[0].object;
        }
    }

    // forEachcc.isolated=(scopefn is null); // Scope is isolated in
    //                                       // strict mode
    // if (scopefn is null) {
    //     scopefn = forEachfn;
    // }

    Value[4] args;
    args[3]=othis;
    auto iter=othis.getIndexIterator(DontEnum, false, k, len);
    foreach(k; iter) {
        Value* v = othis.Get(k);
        if ( (v !is null) ) {
            args[0]=previous;
            args[1]=*v;
            args[2]=k;
            Value* resp=forEachfn.Call(cc, othis, ret, args);
            if (resp !is null) {
                return resp;
            }
        }
        previous=*ret;
    }
    return null;
}

/* ===================== Darray_prototype_indexOf ================= */

Value* Darray_prototype_indexOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist) {
    // ECMA v3 15.4.4.14
    Value cmpval;
    mixin Darray.rangeIndexOf;
    *ret=-1;
    Value* err=calc_range(); // Calculates k and len
    if (err) return err;
    if (arglist.length >= 1) {
        cmpval = arglist[0];
    }

    auto iter=othis.getIndexIterator(DontEnum, false, k, len);
    foreach(k; iter) {
        Value* v = othis.Get(k);
        if ( (v !is null) && !v.isUndefined) {
            if ( *v == cmpval ) {
                *ret=k;
                break;
            }
        }
    }
    return null;
}

/* ===================== Darray_prototype_lastIndexOf ================= */

Value* Darray_prototype_lastIndexOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist) {
    // ECMA v3 15.4.4.15
    Value cmpval;

    mixin Darray.rangeIndexOf;
    *ret=-1;
    Value* err=calc_range(); // Calculates k and len
    if (err) return err;
    if (arglist.length >= 1) {
        cmpval = arglist[0];
    }


    // Reverse iteration
    auto iter=othis.getIndexIterator(DontEnum, true, k, len);
    foreach(k; iter) {
        Value* v = othis.Get(k);
        if ( (v !is null) && !v.isUndefined) {
            if ( *v == cmpval ) {
                *ret=k;
                break;
            }
        }
    }
    return null;
}

/* ===================== Darray_prototype_isArray ================= */

Value* Darray_isArray(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist) {
    // ECMA v5 ------ 15.4.3.2
    *ret=false;
    if (arglist.length >= 1) {
        if(arglist[0].isObject()) {
            *ret = arglist[0].object.isDarray;
        }
    }
    return null;
}


/* =========================== Darray_prototype =================== */

class DarrayPrototype : Darray
{
    alias Dobject.length length;
    this()
    {
        super(Dobject_prototype);
        Dobject f = Dfunction_prototype;

        Put(TEXT_constructor, Darray_constructor, DontEnum, true);

        static enum NativeFunctionData nfd[] =
        [
            { TEXT_toString, &Darray_prototype_toString, 0 },
            { TEXT_toLocaleString, &Darray_prototype_toLocaleString, 0 },
            { TEXT_toSource, &Darray_prototype_toSource, 0 },
            { TEXT_concat, &Darray_prototype_concat, 1 },
            { TEXT_join, &Darray_prototype_join, 1 },
            { TEXT_pop, &Darray_prototype_pop, 0 },
            { TEXT_push, &Darray_prototype_push, 1 },
            { TEXT_reverse, &Darray_prototype_reverse, 0 },
            { TEXT_shift, &Darray_prototype_shift, 0, },
            { TEXT_slice, &Darray_prototype_slice, 2 },
            { TEXT_sort, &Darray_prototype_sort, 1 },
            { TEXT_splice, &Darray_prototype_splice, 2 },
            { TEXT_unshift, &Darray_prototype_unshift, 1 },
            { TEXT_forEach, &Darray_prototype_forEach, 1 },
            { TEXT_reduce, &Darray_prototype_reduce, 2 },
            { TEXT_indexOf, &Darray_prototype_indexOf, 1 },
            { TEXT_lastIndexOf, &Darray_prototype_lastIndexOf, 1 },
         ];

        DnativeFunction.init(this, nfd, DontEnum);

    }
}


/* =========================== Darray =================== */

class Darray : Dobject
{
    protected Value vlength;               // vlength property
    private d_uint32 _ulength;

    this() {
        this(getPrototype());
    }

    this(Dobject prototype) {
        super(prototype);
        scope Value setter=Value(new lengthSetter(this));
        scope Value getter=Value(new lengthGetter(this));

        vlength.putVSetter(&setter);
        vlength.putVGetter(&getter);
        Put(TEXT_length, &vlength, DontDelete|DontEnum, true);
        _ulength = 0;
        classname = TEXT_Array;
    }

    @property uint ulength() {
        return _ulength;
    }

    @property uint ulength(uint len) {
        vlength.putVnumber(len);
        _ulength=len;
        return _ulength;
    }

    class lengthGetter : Dobject {
        Darray owner;
        this(Dobject owner) {
            super(owner);
            this.owner=cast(Darray)owner;
            assert(this.owner, "owner of lengthGetter must be a Darray");
        }

        override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
        {
            *ret=ulength;
            return null;
        }
    }


    class lengthSetter : Dobject {
        Darray owner;
        this(Dobject owner) {
            super(owner);
            this.owner=cast(Darray)owner;
            assert(this.owner, "owner of lengthSetter must be a Darray");
        }

        override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
        {
            if (arglist.length >=0) {
                d_uint32 i=arglist[0].uint32;
                if (i < _ulength) {
                    d_uint32[] todelete;

                    foreach(ref Value key, ref Property p; this) {
                        d_uint32 j;
                        j = key.toUint32();
                        if(j >= i)
                            todelete ~= j;
                    }
                    foreach(d_uint32 j; todelete) {
                        del(j);
                    }
                }
                _ulength=i;
                *ret=_ulength;
            }
            else {
                ret.putVundefined;
                return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_length);
            }
            return null;
        }
    }

    mixin template rangeIndexOf() {
        Value* lenValue;
        d_uint32 len;
        d_uint32 n;
        d_uint32 k=0;
        d_number fromIndex;

        Value* calc_range() {
            // 1.
            lenValue = othis.Get(TEXT_length);
            if(lenValue) {
                auto num=lenValue.toNumber;
                if (num < 0) {
                    *ret=-1;
                    return null;
                }
                // 2.
                len =(lenValue.toNumber>=0)? lenValue.toUint32(): 0;
            }
            if (arglist.length >= 2) {
                if(arglist[1].isPrimitive()) {
                    // fromIndex
                    fromIndex = arglist[1].toNumber;
                }
                if (fromIndex > len) {
                    *ret=-1;
                    return null;
                }
            }
            if ( fromIndex >= 0) {
                // 7.
                k=cast(uint)fromIndex;
            } else {
                // 8.
                if (len > fromIndex) {
                    k =0;
                } else {
                    k=cast(uint)(len-fromIndex); //
                }
            }

            return null;
        }
    }

    override Value* Put(Identifier* key, Value* value, ushort attributes, bool define=false)
    {
        mixin Dobject.SetterT;
        Value* result = put(key.toValue, value, attributes, setter(this), define);
        if(!result) {
            result=Put(key.toText, value, attributes, define);
        }
        return result;
    }

    override Value* Put(d_string name, Value* v, ushort attributes, bool define=false, ushort umask=0)
    {
        mixin Dobject.SetterT;
        d_uint32 i;
        uint c;
        Value* result;
        scope Value vname=Value(name);
        //
        scope d_uint32 dummy;
        if (vname.isArrayIndex(dummy)) {
            define=true; // Use DefineOwnProperty if the it is an
                         // array index
        }
        // ECMA 15.4.5.1
        result = put(&vname, v, attributes, setter(this), define);
        if(!result) {
            i = _ulength;
            long il;
            if ( Value.stringToLong(name, il) && (il >=_ulength) && (il < _ulength.max) ) {
                _ulength=cast(d_uint32)il+1;
            }
        }
        Lret:
        return result;
    }

    override Value* Put(d_string name, Dobject o, ushort attributes, bool define=false) {
        return Put(name, &o.value, attributes, define);
    }

    override Value* Put(d_string PropertyName, d_number n, ushort attributes, bool define=false) {
        Value v;
        v.putVnumber(n);
        return Put(PropertyName, &v, attributes, define);
    }

    override Value* Put(d_string PropertyName, d_string string, ushort attributes, bool define=false) {
        Value v;

        v.putVstring(string);
        return Put(PropertyName, &v, attributes, define);
    }

    override Value* Put(d_uint32 index, Value* vindex, Value* value, ushort attributes, bool define=false)
        in {
            assert(vindex.toUint32 == index);
        }
    out {
        assert(vindex.toHash == Value.calcHash(index));
    }
    body {
        if(index >= _ulength)
            _ulength = index + 1;
        return put(vindex, value, attributes, null, define, vindex.toHash);
    }

    override Value* Put(d_uint32 index, Value* value, ushort attributes, bool define=false)
    {
        if(index >= ulength)
        {
            _ulength = index + 1;
        }

        scope Value vindex=Value(index);
        return put(&vindex, value, attributes, null, define);
    }

    Value* Put(d_uint32 index, d_string string, ushort attributes, bool define=false)
    {
        if(index >= _ulength)
        {
            _ulength = index + 1;
        }

        scope Value vstring=Value(string);
        scope Value vindex=Value(index);
        return put(&vindex, &vstring, attributes, null, define);
    }

    override Value* Get(Identifier* id) {
        return Dobject.Get(id);
    }

    override Value* Get(d_uint32 index) {
        scope Value key=Value(index);
        return get(&key);
    }

    override Value* Get(d_uint32 index, Value* vindex)
        out {
        assert(vindex.toHash == Value.calcHash(index));
    } body {
        scope Value key=Value(index);
        return get(&key, vindex.toHash);
    }

    override bool HasOwnProperty(const Value* key, bool enumerable) {
        return super.HasOwnProperty(key, enumerable);
    }

    override bool Delete(d_string PropertyName) {
        // ECMA 8.6.2.5
        scope Value vname=Value(PropertyName);
        return del(&vname);
    }

    static Dfunction getConstructor() {
        return Darray_constructor;
    }

    static Dobject getPrototype() {
        return Darray_prototype;
    }

    static void init() {
        Darray_constructor = new DarrayConstructor();
        Darray_prototype = new DarrayPrototype();

        static enum NativeFunctionData nfd[] =
        [
           { TEXT_isArray, &Darray_isArray, 1 },
        ];

        DnativeFunction.init(Darray_constructor, nfd, DontEnum);
        Darray_constructor.Put(TEXT_prototype, Darray_prototype, DontEnum |  ReadOnly | DontDelete);
    }
}
