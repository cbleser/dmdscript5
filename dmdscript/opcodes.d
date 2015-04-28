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
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */


module dmdscript.opcodes;

import std.math;

import std.stdio;
import core.stdc.string;
import std.string;
import conv=std.conv;

import dmdscript.script;
import dmdscript.dobject;
import dmdscript.statement;
import dmdscript.functiondefinition;
import dmdscript.value;
import dmdscript.iterator;
import dmdscript.scopex;
import dmdscript.identifier;
import dmdscript.ir;
import dmdscript.errmsgs;
import dmdscript.property;
import dmdscript.ddeclaredfunction;
import dmdscript.dfunction;
import dmdscript.darray;
import dmdscript.text;

//debug=VERIFY;	// verify integrity of code

version = SCOPECACHING;         // turn scope caching on
//version = SCOPECACHE_LOG;	// log statistics on it

// Catch & Finally are "fake" Dobjects that sit in the scope
// chain to implement our exception handling context.

class Catch : Dobject
{
    // This is so scope_get() will skip over these objects
    override Value* Get(d_string PropertyName) const
    {
        return null;
    }
/+
    override Value* Get(d_string PropertyName, hash_t hash) const
    {
        return null;
    }
+/
    // This is so we can distinguish between a real Dobject
    // and these fakers
    override d_string getTypeof() const
    {
        return null;
    }

    sizediff_t offset;        // offset of CatchBlock
    d_string name;      // catch identifier

    this(sizediff_t offset, d_string name)
    {
        super(null);
        this.offset = offset;
        this.name = name;
    }

    override bool isCatch() const
    {
        return true;
    }
}

class Finally : Dobject
{
    override Value* Get(d_string PropertyName) const
    {
        return null;
    }
/+
    override Value* Get(d_string PropertyName, hash_t hash) const
    {
        return null;
    }
+/
    override d_string getTypeof() const
    {
        return null;
    }

    IR *finallyblock;    // code for FinallyBlock

    this(IR * finallyblock)
    {
        super(null);
        this.finallyblock = finallyblock;
    }

    override bool isFinally() const
    {
        return true;
    }
}


/************************
 * Look for identifier in scope.
 */

Value* scope_get(Dobject[] scopex, Identifier* id, Dobject *pthis)
{
    size_t d;
    Dobject o;
    Value* v;

    //writef("scope_get: scope = %p, scope.data = %p\n", scopex, scopex.data);
    //writefln("scope_get: scopex = %x, length = %d, id = %s", cast(uint)scopex.ptr, scopex.length, id.toText);
    d = scopex.length;
    for(;; )
    {
        if(!d)
        {
            v = null;
            *pthis = null;
            break;
        }
        d--;
        o = scopex[d];
        //writef("o = %x, hash = x%x, s = '%s'\n", o, hash, s);
        v = o.Get(id);
        if(v)
        {
            *pthis = o;
            break;
        }
    }
    return v;
}

Value* scope_get_lambda(Dobject[] scopex, Identifier* id, ref Dobject pthis)
{
    size_t d;
    Dobject o;
    Value* v;

    d = scopex.length;
    for(;; )
    {
        if(!d)
        {
            v = null;
            pthis = null;
            break;
        }
        d--;
        o = scopex[d];
        v = o.Get(id);
        if(v)
        {
            pthis = o;
            break;
        }
    }
    //writefln("v = %x", cast(uint)cast(void*)v);
    return v;
}

Value* scope_get(Dobject[] scopex, Identifier* id)
{
    uint d;
    Dobject o;
    Value* v;

    //writefln("scope_get: scopex = %x, length = %d, id = %s", cast(uint)scopex.ptr, scopex.length, id.toText);
    d = cast(uint)scopex.length;
    // 1 is most common case for d
    if(d == 1)
    {
        return scopex[0].Get(id);
    }
    for(;; )
    {
        if(!d)
        {
            v = null;
            break;
        }
        d--;
        o = scopex[d];
        //writefln("\to = %s", o);
        v = o.Get(id);
        if(v)
            break;
        //writefln("\tnot found");
    }
    return v;
}

/************************************
 * Find last object in scopex, null if none.
 */

Dobject scope_tos(Dobject[] scopex)
{
    uint d;
    Dobject o;

    for(d = cast(uint)scopex.length; d; )
    {
        d--;
        o = scopex[d];
        if(o.getTypeof() != null)  // if not a Finally or a Catch
            return o;
    }
    return null;
}


void PutValue(CallContext *cc, Identifier* id, Value* a, bool check_lvalue_defined)
{
    mixin Dobject.SetterT;
    // ECMA v3 8.7.2
    // Look for the object o in the scope chain.
    // If we find it, put its value.
    // If we don't find it, put it into the global object

    size_t d;
    Value* v;
    Dobject o;
    //a.checkReference();
    d = cc.scopex.length;
    if(d == cc.globalroot)
    {
        o = scope_tos(cc.scopex);
        if (check_lvalue_defined) {
            if (!o.HasOwnProperty(id, false)) {
                throw new ErrorValue(Dobject.ReferenceError(cc.errorInfo, errmsgtbl[ERR_LVALUE_NOT_DEFINED],id.toText));
            }
        }

    }
    else
    {
        for(;; d--)
        {
            assert(d > 0);
            o = cc.scopex[d - 1];
            v = o.Get(id);
            if(v)
            {
                v.checkReference();
                break;// Overwrite existing property with new one
            }
            if(d == cc.globalroot) {
                if (check_lvalue_defined) {
                    throw new ErrorValue(Dobject.ReferenceError(cc.errorInfo, errmsgtbl[ERR_LVALUE_NOT_DEFINED],id.toText));
                }

                break;
            }
        }
    }
    o.Put(id, a, 0);
}


/*****************************************
 * Helper function for Values that cannot be converted to Objects.
 */

Value* cannotConvert(Value* b, int linnum)
{
    ErrInfo errinfo;

    errinfo.linnum = linnum;
    if(b.isUndefinedOrNull())
    {
        b = Dobject.RuntimeError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_CANNOT_CONVERT_TO_OBJECT4],
                                 b.getType());
    }
    else
    {
        b = Dobject.RuntimeError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_CANNOT_CONVERT_TO_OBJECT2],
                                 b.getType(), b.toText);
    }
    return b;
}

const uint INDEX_FACTOR = Value.sizeof;   // or 1

struct IR
{
    static d_boolean trace;
    static uint strict_cmd;
    union
    {
        struct
        {
            version(LittleEndian)
            {
                IRcode opcode;
                ubyte padding; // dummy
                ushort linnum;
                version(D_LP64)
                    uint dummy;
            }
            else
            {
                version(D_LP64)
                uint dummy;
                ushort linnum;
                ubyte  padding; // dummy
                IRcode opcode;
            }
        }
        IR* code;
        Value*      value;
        size_t      index;      // index into local variable table
        hash_t      hash;       // cached hash value
        sizediff_t  offset;
        Identifier* id;
        d_boolean   boolean;
        version(D_LP64) {
            d_number    number;
        }
        Statement   target;     // used for backpatch fixups
        Dobject     object;
        void*       ptr;
    }

    uint linenum() const {
        return linnum;
    }


    /****************************
     * This is the main interpreter loop.
     */

    static Value *call(CallContext *cc, Dobject othis,
                       IR *code, Value* ret, Value* locals) {
        Value* a;
        Value* b;
        Value* c;
        Value* v;
        Iterator *iter;
        Identifier *id;
        d_string s;
        d_string s2;
        d_number n;
        d_boolean bo;
        d_int32 i32;
        d_uint32 u32;
        d_boolean res;
        d_string tx;
        d_string ty;
        Dobject owork;
        Dobject[] scopex;
        size_t dimsave;
        sizediff_t offset;
        Catch ca;
        Finally f;
        IR* codestart = code;
//        std.stdio.writefln("\tIR.call iseval=%s",cc.iseval);
        //Finally blocks are sort of called, sort of jumped to
        //So we are doing "push IP in some stack" + "jump"
        IR*[] finallyStack;      //it's a stack of backreferences for finally
        d_number inc;
        mixin Dobject.SetterT;
        Setter value_setter(Value* val) {
            if (val.isObject) {
                return setter(val.toObject);
            }
            return null;
        }
        /* Set current Call Context to support setters ang getters*/
        CallContext.currentcc=cc;
//        std.stdio.writefln("IR.call %x", cast(void*)othis);
//        bool store_use_strict=cc.use_strict;
        // auto save_strict_mode=cc.strict_mode;
        // std.stdio.writeln("\t>> strict_mode=",save_strict_mode);
        // scope(exit) {
        //     cc.strict_mode=save_strict_mode;
        //     std.stdio.writeln("\t<< strict_mode=",save_strict_mode);
        // }

        void callFinally(Finally f) {
            //cc.scopex = scopex;
            finallyStack ~= code;
            code = f.finallyblock;
        }
        Value* unwindStack(Value* err){
            assert(scopex.length && scopex[0] !is null,"Null in scopex, Line " ~ conv.to!string(code.linnum));
            a = err;
            //a.getErrInfo(null, GETlinnum(code));

            for(;; )
            {
                if(scopex.length <= dimsave)
                {
                    ret.putVundefined();
                    // 'a' may be pointing into the stack, which means
                    // it gets scrambled on return. Therefore, we copy
                    // its contents into a safe area in CallContext.
                    static assert(cc.value.sizeof == Value.sizeof);
                    Value.copy(&cc.value, a);
                    return &cc.value;
                }
                owork = scopex[$ - 1];
                scopex = scopex[0 .. $ - 1];            // pop entry off scope chain

                if(owork.isCatch())
                {
                    ca = cast(Catch)owork;
                    owork = new Dobject(Dobject.getPrototype());
                    version(JSCRIPT_CATCH_BUG)
                    {
                        PutValue(cc, ca.name, a);
                    }
                    else
                    {
                        owork.Put(ca.name, a, DontDelete);
                    }
                    scopex ~= owork;
                    cc.scopex = scopex;
                    code = codestart + ca.offset;
                    break;
                }
                else
                {
                    if(owork.isFinally())
                    {
                        f = cast(Finally)owork;
                        callFinally(f);
                        break;
                    }
                }
            }
            return null;
        }
        /***************************************
         * Cache for getscope'svoid
         */
        version(SCOPECACHING)
        {
            struct ScopeCache
            {
                d_string s;
                Value*   v;     // never null, and never from a Dcomobject
            }
            int si;
            ScopeCache zero;
            ScopeCache[16] scopecache;
            version(SCOPECACHE_LOG)
                int scopecache_cnt = 0;

            uint SCOPECACHE_SI(immutable(wchar)* s)// pure
            {
                return (cast(uint)(s)) & 15;
            }
            void SCOPECACHE_CLEAR()
            {
                scopecache[] = zero;
            }
            bool SCOPECACHE_CHECK(d_string s) //pure
            {
                return scopecache[SCOPECACHE_SI(s.ptr)].s == s;
            }
        }
        else
        {
            uint SCOPECACHE_SI(immutable(tchar)* s) pure
            {
                return 0;
            }
            void SCOPECACHE_CLEAR()
            {
            }
            bool SCOPECACHE_CHECK(immutable(tchar)* s) pure
            {
                return false;
            }
        }

        version(all)
        {
            // Eliminate the scale factor of Value.sizeof by computing it at compile time
            Value* GETa(IR* code)
            {
                return cast(Value*)(cast(void*)locals + (code + 1).index );
            }
            Value* GETb(IR* code)
            {
                return cast(Value*)(cast(void*)locals + (code + 2).index );
            }
            Value* GETc(IR* code)
            {
                return cast(Value*)(cast(void*)locals + (code + 3).index );
            }
            Value* GETd(IR* code)
            {
                return cast(Value*)(cast(void*)locals + (code + 4).index );
            }
            Value* GETe(IR* code)
            {
                return cast(Value*)(cast(void*)locals + (code + 5).index );
            }
        }
        else
        {
            Value* GETa(IR* code)
            {
                return &locals[(code + 1).index];
            }
            Value* GETb(IR* code)
            {
                return &locals[(code + 2).index];
            }
            Value* GETc(IR* code)
            {
                return &locals[(code + 3).index];
            }
            Value* GETd(IR* code)
            {
                return &locals[(code + 4).index];
            }
            Value* GETe(IR* code)
            {
                return &locals[(code + 5).index];
            }
        }

        // ErrInfo GETinfo(IR* code) {
        //     ErrInfo result;
        //     result.linnum=code.linnum;
        //     return result;
        // }

        // void GETInfo(ContextCall* cc, IR* code) {
        //     cc.code=code;
        // }

        debug(VERIFY) uint checksum = IR.verify(__LINE__, code);

        version(none)
        {
            writefln("+printfunc");
            printfunc(code);
            writefln("-printfunc");
        }
        scopex = cc.scopex;
        //printf("call: scope = %p, length = %d\n", scopex.ptr, scopex.length);
        dimsave = scopex.length;
        //if (logflag)
        //    writef("IR.call(othis = %p, code = %p, locals = %p)\n",othis,code,locals);

        //debug
        version(none) //no data field in scop struct
        {
            uint debug_scoperoot = cc.scoperoot;
            uint debug_globalroot = cc.globalroot;
            uint debug_scopedim = scopex.length;
            uint debug_scopeallocdim = scopex.allocdim;
            Dobject debug_global = cc.global;
            Dobject debug_variable = cc.variable;

            void** debug_pscoperootdata = cast(void**)mem.malloc((void*).sizeof * debug_scoperoot);
            void** debug_pglobalrootdata = cast(void**)mem.malloc((void*).sizeof * debug_globalroot);

            memcpy(debug_pscoperootdata, scopex.data, (void*).sizeof * debug_scoperoot);
            memcpy(debug_pglobalrootdata, scopex.data, (void*).sizeof * debug_globalroot);
        }

        assert(code);
        if (IR.trace) writefln("trace is on %x",cast(void*)othis);

        if (!othis) {
            a=Dobject.ReferenceError(cc.errorInfo(code), errmsgtbl[ERR_NOT_AN_OBJECT],TEXT_TypeError,"undefined of null");
            // Throw
            v=unwindStack(a);
            if (v)
                return v;
        }
//        assert(othis);

        for(;; )
        {
            Lnext:
            //writef("cc = %x, interrupt = %d\n", cc, cc.Interrupt);
            if(cc.Interrupt)                    // see if script was interrupted
                goto Linterrupt;
            try{
                version(none)
                {
                    writef("Scopex len: %d ",scopex.length);
                    writef("%2d:", code - codestart);
                    print(code - codestart, code);
                    writeln();
                }

                //debug
                version(none) //no data field in scop struct
                {
                    assert(scopex == cc.scopex);
                    assert(debug_scoperoot == cc.scoperoot);
                    assert(debug_globalroot == cc.globalroot);
                    assert(debug_global == cc.global);
                    assert(debug_variable == cc.variable);
                    assert(scopex.length >= debug_scoperoot);
                    assert(scopex.length >= debug_globalroot);
                    assert(scopex.length >= debug_scopedim);
                    assert(scopex.allocdim >= debug_scopeallocdim);
                    assert(0 == memcmp(debug_pscoperootdata, scopex.data, (void*).sizeof * debug_scoperoot));
                    assert(0 == memcmp(debug_pglobalrootdata, scopex.data, (void*).sizeof * debug_globalroot));
                    assert(scopex);
                }

                //writef("\t%d# IR%d:\n", code.opcode);
                if ( IR.trace ) {
                    writef("%d:",cast(uint)(code-codestart));
                    IR.print(cast(uint)(code-codestart),code);
                }
                with(IRcode) final switch(code.opcode)
                {
                case IRerror:
                    assert(0);
                case IRend:
                    a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_UNEXPECTED_END],
                                                 );
                    return a;
                    break;
                case IRnop:
                    code++;
                    break;

                case IRget:                 // a = b.c
                    a = GETa(code);
                    b = GETb(code);
                    if ( b.isUndefined ) {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                            errmsgtbl[ERR_UNDEFINED_OBJECT]);
                        goto Lthrow;
                    } else if ( b.isNull ) {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                            errmsgtbl[ERR_NULL_OBJECT]);
                        goto Lthrow;
                    }
                    c = GETc(code);
                    bool isindex=c.isArrayIndex(u32);
                    if (b.isString && isindex) {
                        Value vret; v=&vret;
                        b.charAt(u32, &vret);
                    } else {
                        owork = b.toObject();
                        if(!owork) {
                            a = cannotConvert(b, code.linenum());
                            goto Lthrow;
                        }

                        if ( isindex ) {
                            if (!c.isInt) {
                                Value vindex;
                                vindex.putVuint32(u32);
                                //    vindex.toHash;
                                c=&vindex;
                            }
                            c.toHash;
                            //writef("IRget %d\n", i32);
                            v = owork.Get(u32, c);
                        } else {
                            s = c.toText;
                            v = owork.Get(s);
                        }
                    }
                    if(!v)
                        v = &Value.vundefined;
                    Value.copy(a, v);
                    code += 4;
                    break;

                case IRput:                 // b.c = a
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    if(c.isNumber() &&
                       (i32 = cast(d_int32)c.number) == c.number &&
                       i32 >= 0)
                    {
                        //writef("IRput %d\n", i32);
                        if(b.isObject()) {
                            a = b.object.Put(cast(d_uint32)i32, c, a, 0);
                        } else {
                            a = b.Put(cast(d_uint32)i32, c, a);
                        }
                    }
                    else
                    {
                        s = c.toText;
                        a = b.Put(s, a);
                    }
                    if(a)
                        goto Lthrow;
                    code += 4;
                    break;

                case IRgets:                // a = b.s
                    a = GETa(code);
                    b = GETb(code);
                    if ( b.isUndefined )  {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                            errmsgtbl[ERR_UNDEFINED_OBJECT]);
                        goto Lthrow;
                    } else if ( b.isNull ) {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                            errmsgtbl[ERR_NULL_OBJECT]);
                        goto Lthrow;
                    }

                    s = (code + 3).id.toText;
                    owork = b.toObject();
                    if(!owork)
                    {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_CANNOT_CONVERT_TO_OBJECT3],
                                                 b.getType(), b.toText,
                                                 s);
                        goto Lthrow;
                    }
                    v = owork.Get(s);
                    if(!v)
                    {
                        //writef("IRgets: %s.%s is undefined\n", b.getType(), d_string_ptr(s));
                        v = &Value.vundefined;
                    }
                    Value.copy(a, v);
                    code += 4;
                    goto Lnext;
                case IRcheckref: // s
                    id = (code+1).id;
                    s = id.toText;
                    if(!scope_get(scopex, id)) {
                        throw new ErrorValue(Dobject.ReferenceError(cc.errorInfo(code), errmsgtbl[ERR_UNDEFINED_VAR],s));
                    }
                    code += 2;
                    break;
                case IRgetscope:            // a = s
                    a = GETa(code);
                    id = (code + 2).id;
                    s = id.toText;
                    version(SCOPECACHING)
                    {
                        si = SCOPECACHE_SI(s.ptr);
                         if(s is scopecache[si].s)
                        {
                            version(SCOPECACHE_LOG)
                                scopecache_cnt++;
                            Value.copy(a, scopecache[si].v);
//
                            v = scope_get(scopex,id);
                            // std.stdio.writefln("cache[%d]=%12X.%s v=%12X.%s equal=%s %s",si,
                            //     scopecache[si].v,scopecache[si].v.vtype,
                            //     v,v.vtype,scopecache[si].v is v, s);
//
                            code += 3;
                            break;
                        }
                        //writefln("miss %s, was %s, s.ptr = %x, cache.ptr = %x", s, scopecache[si].s, cast(uint)s.ptr, cast(uint)scopecache[si].s.ptr);
                    }
                    version(all)
                    {
                        v = scope_get(scopex,id);
                        if(!v){
                            v = signalingUndefined(s);

                            PutValue(cc,id,v, false);
                            // Delete undefined id after used
                            //version(none) {

                            if(scope_get(scopex, id, &owork)) {
                                if(owork.implementsDelete())
                                    owork.Delete(s);
                                else
                                    owork.HasProperty(s);
                            }

                         }
                        else
                        {
                            // if (v.vtype is vtype_t.V_UNDEFINED) {
                            //     ErrInfo errinfo=GETinfo(code);
                            //     a = Dobject.RuntimeError(&errinfo,
                            //         errmsgtbl[ERR_UNDEFINED_OBJECT]);
                            //     goto Lthrow;
                            // }

                            version(SCOPECACHING)
                            {
                                if(1) //!o.isDcomobject())
                                {
                                    //  std.stdio.writefln("Cache[%d] %12X %s",si,v,s);
                                    scopecache[si].s = s;
                                    scopecache[si].v = v;
                                }
                            }
                        }
                    }
                    //writef("v = %p\n", v);
                    //writef("v = %g\n", v.toNumber());
                    //writef("v = %s\n", d_string_ptr(v.toText));
                    Value.copy(a, v);

                    code += 3;
                    break;

                case IRaddass:              // a = (b.c += a)
                    c = GETc(code);
                    s = c.toText;
                    goto Laddass;

                case IRaddasss:             // a = (b.s += a)
                    s = (code + 3).id.toText;
                    Laddass:
                    b = GETb(code);
                    v = b.Get(s);
                    goto Laddass2;

                case IRaddassscope:         // a = (s += a)
                    b = null;               // Needed for the b.Put() below to shutup a compiler use-without-init warning
                    id = (code + 2).id;
                    s = id.toText;
                    version(SCOPECACHING)
                    {
                        si = SCOPECACHE_SI(s.ptr);
                        if(s is scopecache[si].s)
                            v = scopecache[si].v;
                        else
                            v = scope_get(scopex, id);
                    }
                    else
                    {
                        v = scope_get(scopex, id);
                    }
                    Laddass2:
                    a = GETa(code);
                    if(!v)
                    {
                        throw new ErrorValue(Dobject.ReferenceError(cc.errorInfo(code), errmsgtbl[ERR_UNDEFINED_VAR],s));
                    }
                    else if(a.isNumber() && v.isNumber())
                    {
                        (*a) = a.number + v.number;
                        (*v) = a.number;
                    }
                    else {
                        b=v.toPrimitive(v, null);
                        if (b) {
                            a=b;
                            goto Lthrow;
                        }
                        b=a.toPrimitive(a, null);
                        if (b) {
                            a=b;
                            goto Lthrow;
                        }
                        if(v.isString())
                        {
                            s2 = v.toText ~ a.toText;
                            a.putVstring(s2);
                            Value.copy(v, a);
                        }
                        else if(a.isString())
                        {
                            s2 = v.toText ~a.toText;
                            a.putVstring(s2);
                            Value.copy(v, a);
                        }
                        else
                        {
                            a.putVnumber(a.toNumber() + v.toNumber());
                            *v = *a;//full copy
                        }
                    }
                    code += 4;
                    break;

                case IRputs:            // b.s = a
                    a = GETa(code);
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                    {
                        a = cannotConvert(b, code.linenum);
                        goto Lthrow;
                    }
                    a = owork.Put((code + 3).id.toText, a, 0);
                    if(a)
                        goto Lthrow;
                    code += 4;
                    goto Lnext;
               case IRputSet:            // b {set s a}
                    a = GETa(code);
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                    {
                        a = cannotConvert(b, code.linenum);
                        goto Lthrow;
                    }
                    Value set; set.putVSetter(a);
                    a = owork.Put((code + 3).id.toText, &set, 0, true);
                    if(a)
                        goto Lthrow;
                    code += 4;
                    goto Lnext;
                case IRputGet:            // b {get s a}
                    a = GETa(code);
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                    {
                        a = cannotConvert(b, code.linenum);
                        goto Lthrow;
                    }
                    Value get; get.putVGetter(a);
                    a = owork.Put((code + 3).id.toText, &get, 0, true);
                    if(a)
                        goto Lthrow;
                    code += 4;
                    goto Lnext;

                case IRputscope:            // s = a
                    a = GETa(code);
                    a.checkReference();
                    PutValue(cc, (code + 2).id, a, cc.isStrictMode);
                    code += 3;
                    break;

                case IRputdefault:              // b = a
                    a = GETa(code);
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                    {
                        cc.code=code;
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_CANNOT_ASSIGN], a.getType(),
                                                 b.getType());
                        goto Lthrow;
                    }
                    a = owork.PutDefault(a);
                    if(a)
                        goto Lthrow;
                    code += 3;
                    break;

                case IRputthis:             // s = a
                    //a = cc.variable.Put((code + 2).id.value.string, GETa(code), DontDelete);
                    owork = scope_tos(scopex);
                    assert(owork);
                    if(owork.HasProperty((code + 2).id.toText))
                        a = owork.Put((code+2).id.toText,GETa(code),DontDelete);
                    else
                        a = cc.variable.Put((code + 2).id.toText, GETa(code), DontDelete);
                    if (a) goto Lthrow;
                    code += 3;
                    break;

                case IRmov:                 // a = b
                    b=GETb(code);
                    // std.stdio.writefln("copy %s to %s", GETb(code).toInfo, GETa(code).toInfo);
                    // std.stdio.writeln("b=",b.toInfo, (b.protect & ReadOnly)==0);
                    if ( (b.protect & ReadOnly) ==0 ) {
                        Value.copy(GETa(code), b);
                    } else {
                        if (cc.isStrictMode) {
                            cc.code=code;
                            a=Dobject.RuntimeError(cc.errorInfo(code), errmsgtbl[ERR_READONLY], GETa(code).toText);
                            goto Lthrow;
                        }
                    }

                    //     std.stdio.writeln("Dont copy");
                    // }
                    code += 3;
                    break;

                case IRstring:              // a = "string"
                    GETa(code).putVstring((code + 2).id.toText);
                    code += 3;
                    break;

                case IRobject: {              // a = object
                    FunctionDefinition fd;
                    fd = cast(FunctionDefinition)(code + 2).ptr;
                    Dfunction fobject = new DdeclaredFunction(fd);
                    fobject.scopex = scopex;

/*
                    if ( cc.isStrictMode) {
                        std.stdio.writeln("#### LOCAL SCOPE");
                        auto localscope=new ValueObject(&Value.vundefined, TEXT_undefined);
                        fobject.scopex~=cc.global;
                        fobject.scopex~=localscope;

                    } else {
                        fobject.scopex = scopex;
                    }
*/
                    GETa(code).putVobject(fobject);
                    code += 3;
                    break;
                }

                case IRthis:                // a = this
                    // if ( cc.isStrictMode && cc.isolated ) {
                    //     GETa(code).putVundefined;
                    // } else {
//                    std.stdio.writefln("othis = %x",cast(void*)othis);
                    ValueObject vobj=cast(ValueObject)othis;
                    if (vobj) {
                        *GETa(code)=vobj.value;
                    } else {
                        GETa(code).putVobject(othis);
                    }
                    // }
                    code += 2;
                    break;

                case IRnumber:              // a = number
				  version(D_LP64) {
                      a=GETa(code);
                      GETa(code).putVnumber((code + 2).number);
                      code += 3;
				  } else {
                    GETa(code).putVnumber(*cast(d_number *)(code + 2));
                    code += 4;
				  }
                    break;

                case IRboolean:             // a = boolean
                    GETa(code).putVboolean((code + 2).boolean);
                    code += 3;
                    break;

                case IRnull:                // a = null
                    GETa(code).putVnull();
                    code += 2;
                    break;

                case IRundefined:           // a = undefined
                    GETa(code).putVundefined();
                    code += 2;
                    break;

                case IRthisget:             // a = othis.ident
                    a = GETa(code);
                    v = othis.Get((code + 2).id.toText);
                    if(!v)
                        v = &Value.vundefined;
                    Value.copy(a, v);
                    code += 3;
                    break;

                case IRneg:                 // a = -a
                    a = GETa(code);
                    n = a.toNumber();
                    a.putVnumber(-n);
                    code += 2;
                    break;

                case IRpos:                 // a = a
                    a = GETa(code);
                    n = a.toNumber();
                    a.putVnumber(n);
                    code += 2;
                    break;

                case IRcom:                 // a = ~a
                    a = GETa(code);
                    i32 = a.toInt32();
                    a.putVnumber(~i32);
                    code += 2;
                    break;

                case IRnot:                 // a = !a
                    a = GETa(code);
                    a.putVboolean(!a.toBoolean());
                    code += 2;
                    break;

                case IRtypeof:      // a = typeof a
                    // ECMA 11.4.3 says that if the result of (a)
                    // is a Reference and GetBase(a) is null,
                    // then the result is "undefined". I don't know
                    // what kind of script syntax will generate this.
                    a = GETa(code);
                    a.putVstring(a.getTypeof());
                    code += 2;
                    break;

                case IRinstance:        // a = b instanceof c
                {
                    Dobject co;

                    // ECMA v3 11.8.6

                    b = GETb(code);
                    owork = b.toObject();
                    c = GETc(code);
                    if(c.isPrimitive())
                    {
                        cc.code=code;
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_RHS_MUST_BE_OBJECT],
                                                 "instanceof", c.getType());
                        goto Lthrow;
                    }
                    co = c.toObject();
                    a = GETa(code);
                    v = cast(Value*)co.HasInstance(a, b);
                    if(v)
                    {
                        a = v;
                        goto Lthrow;
                    }
                    code += 4;
                    break;
                }
                case IRadd:                     // a = b + c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);

                    if(b.isNumber() && c.isNumber())
                    {
                        a.putVnumber(b.number + c.number);
                    }
                    else
                    {
                        Value vtmpb;
                        Value vtmpc;
                        Value* vb = &vtmpb;
                        Value* vc = &vtmpc;

                        v=b.toPrimitive(vb, null);
                        if (v) {
                            a=v;
                            goto Lthrow;
                        }
                        v=c.toPrimitive(vc, null);
                        if (v) {
                            a=v;
                            goto Lthrow;
                        }


                        if(vb.isString() || vc.isString())
                        {
                            s = vb.toText ~ vc.toText;
                            a.putVstring(s);
                        }
                        else
                        {
                            a.putVnumber(vb.toNumber() + vc.toNumber());
                        }
                    }

                    code += 4;
                    break;

                case IRsub:                 // a = b - c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    a.putVnumber(b.toNumber() - c.toNumber());
                    code += 4;
                    break;

                case IRmul:                 // a = b * c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    a.putVnumber(b.toNumber() * c.toNumber());
                    code += 4;
                    break;

                case IRdiv:                 // a = b / c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);

                    //writef("%g / %g = %g\n", b.toNumber() , c.toNumber(), b.toNumber() / c.toNumber());
                    a.putVnumber(b.toNumber() / c.toNumber());
                    code += 4;
                    break;

                case IRmod:                 // a = b % c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    a.putVnumber(b.toNumber() % c.toNumber());
                    code += 4;
                    break;

                case IRshl:                 // a = b << c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    i32 = b.toInt32();
                    u32 = c.toUint32() & 0x1F;
                    i32 <<= u32;
                    a.putVnumber(i32);
                    code += 4;
                    break;

                case IRshr:                 // a = b >> c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    i32 = b.toInt32();
                    u32 = c.toUint32() & 0x1F;
                    i32 >>= cast(d_int32)u32;
                    a.putVnumber(i32);
                    code += 4;
                    break;

                case IRushr:                // a = b >>> c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    i32 = b.toUint32();
                    u32 = c.toUint32() & 0x1F;
                    u32 = (cast(d_uint32)i32) >> u32;
                    a.putVnumber(u32);
                    code += 4;
                    break;

                case IRand:         // a = b & c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    a.putVnumber(b.toInt32() & c.toInt32());
                    code += 4;
                    break;

                case IRor:          // a = b | c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    a.putVnumber(b.toInt32() | c.toInt32());
                    code += 4;
                    break;

                case IRxor:         // a = b ^ c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    a.putVnumber(b.toInt32() ^ c.toInt32());
                    code += 4;
                    break;
                case IRin:          // a = b in c
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    s = b.toText;
                    owork = c.toObject();
                    if(!owork || !c.isObject()){
                        cc.code=code;
                        throw new ErrorValue(Dobject.RuntimeError(cc.errorInfo(code),errmsgtbl[ERR_RHS_MUST_BE_OBJECT],"in",c.toText));
                    }
                    a.putVboolean(owork.HasProperty(s));
                    code += 4;
                    break;

                /********************/

                case IRpreinc:     // a = ++b.c
                    c = GETc(code);
                    s = c.toText;
                    goto Lpreinc;
                case IRpreincs:    // a = ++b.s
                    s = (code + 3).id.toText;
                    Lpreinc:
                    inc = 1;
                    Lpre:
                    a = GETa(code);
                    b = GETb(code);
                    v = b.Get(s);
                    if(!v)
                        v = &Value.vundefined;
                    n = v.toNumber();
                    a.putVnumber(n + inc);
                    b.Put(s, a);
                    code += 4;
                    break;

                case IRpreincscope:        // a = ++s
                    inc = 1;
                    Lprescope:
                    a = GETa(code);
                    id = (code + 2).id;
                    s = id.toText;
                    version(SCOPECACHING)
                    {
                        si = SCOPECACHE_SI(s.ptr);
                        if(s is scopecache[si].s)
                        {
                            v = scopecache[si].v;
                            n = v.toNumber() + inc;
                            v.putVnumber(n);
                            a.putVnumber(n);
                        }
                        else
                        {
                            v = scope_get(scopex, id, &owork);
                            if(v)
                            {
                                n = v.toNumber() + inc;
                                v.putVnumber(n);
                                a.putVnumber(n);
                            }
                            else
                            {
                                //FIXED: as per ECMA v5 should throw ReferenceError
                                cc.code=code;
                                a = Dobject.ReferenceError(cc.errorInfo(code), errmsgtbl[ERR_UNDEFINED_VAR], s);

                                //a.putVundefined();
                                goto Lthrow;
                            }
                        }
                    }
                    else
                    {

                        v = scope_get(scopex, id, &o);
                        if(v)
                        {
                            n = v.toNumber();
                            v.putVnumber(n + inc);
                            Value.copy(a, v);
                        }
                        else
                        {
                            throw new ErrorValue(Dobject.ReferenceError(errmsgtbl[ERR_UNDEFINED_VAR], s));
                        }
                    }
                    code += 4;
                    break;

                case IRpredec:     // a = --b.c
                    c = GETc(code);
                    s = c.toText;
                    goto Lpredec;
                case IRpredecs:    // a = --b.s
                    s = (code + 3).id.toText;
                    Lpredec:
                    inc = -1;
                    goto Lpre;

                case IRpredecscope:        // a = --s
                    inc = -1;
                    goto Lprescope;

                /********************/

                case IRpostinc:     // a = b.c++
                    c = GETc(code);
                    s = c.toText;
                    goto Lpostinc;
                case IRpostincs:    // a = b.s++
                    s = (code + 3).id.toText;
                    Lpostinc:
                    a = GETa(code);
                    b = GETb(code);
                    v = b.Get(s);
                    if(!v)
                        v = &Value.vundefined;
                    n = v.toNumber();
                    a.putVnumber(n + 1);
                    b.Put(s, a);
                    a.putVnumber(n);
                    code += 4;
                    break;

                case IRpostincscope:        // a = s++
                    id = (code + 2).id;
                    v = scope_get(scopex, id, &owork);
                    if(v && v != &Value.vundefined)
                    {
                        a = GETa(code);
                        n = v.toNumber();
                        v.putVnumber(n + 1);
                        a.putVnumber(n);
                    }
                    else
                    {
                        //GETa(code).putVundefined();
                        //FIXED: as per ECMA v5 should throw ReferenceError
                        cc.code=code;
                        throw new ErrorValue(Dobject.ReferenceError(cc.errorInfo(code), id.toText));
                        //v = signalingUndefined(id.value.string);
                    }
                    code += 3;
                    break;

                case IRpostdec:     // a = b.c--
                    c = GETc(code);
                    s = c.toText;
                    goto Lpostdec;
                case IRpostdecs:    // a = b.s--
                    s = (code + 3).id.toText;
                    Lpostdec:
                    a = GETa(code);
                    b = GETb(code);
                    v = b.Get(s);
                    if(!v)
                        v = &Value.vundefined;
                    n = v.toNumber();
                    a.putVnumber(n - 1);
                    b.Put(s, a);
                    a.putVnumber(n);
                    code += 4;
                    break;

                case IRpostdecscope:        // a = s--
                    id = (code + 2).id;
                    v = scope_get(scopex, id, &owork);
                    if(v && v != &Value.vundefined)
                    {
                        n = v.toNumber();
                        a = GETa(code);
                        v.putVnumber(n - 1);
                        a.putVnumber(n);
                    }
                    else
                    {
                        //GETa(code).putVundefined();
                        //FIXED: as per ECMA v5 should throw ReferenceError
                        throw new ErrorValue(Dobject.ReferenceError(cc.errorInfo(code), id.toText));
                        //v = signalingUndefined(id.value.string);
                    }
                    code += 3;
                    break;

                case IRdel:     // a = delete b.c
                case IRdels:    // a = delete b.s
                    b = GETb(code);
                    if(b.isPrimitive())
                        bo = true;
                    else
                    {
                        owork = b.toObject();
                        if(!owork)
                        {
                            a = cannotConvert(b, code.linenum);
                            goto Lthrow;
                        }
                        s = (code.opcode == IRdel)
                            ? GETc(code).toText
                            : (code + 3).id.toText;
                        if(owork.implementsDelete())
                            bo = owork.Delete(s);
                        else
                            bo = !owork.HasProperty(s);
                    }
                    GETa(code).putVboolean(bo);
                    code += 4;
                    break;

                case IRdelscope:    // a = delete s
                    id = (code + 2).id;
                    s = id.toText;
                    //o = scope_tos(scopex);		// broken way
                    if(!scope_get(scopex, id, &owork))
                        bo = true;
                    else if(owork.implementsDelete())
                        bo = owork.Delete(s);
                    else
                        bo = !owork.HasProperty(s);
                    GETa(code).putVboolean(bo);
                    code += 3;
                    break;

                /* ECMA requires that if one of the numeric operands is NAN,
                 * then the result of the comparison is false. D generates a
                 * correct test for NAN operands.
                 */

                case IRclt:         // a = (b <   c)
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    Value flag;
                    v=b.abstractRelationComparision(c, &flag, false);
                    if (v) {
                        a=v;
                        goto Lthrow;
                    }

                    if (flag.isUndefined) {
                        a.putVboolean(false);
                    } else {
                        a.putVboolean(flag == -1);
                    }
                    code += 4;
                    break;
                case IRcle:         // a = (b <=  c)
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    Value flag;
                    b.abstractRelationComparision(c, &flag, false);
                    if (flag.isUndefined) {
                        a.putVboolean(false);
                    } else {
                        a.putVboolean(flag != 1);
                    }
                    code += 4;
                    break;
                case IRcgt:         // a = (b >   c)
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    Value flag;
                    v=b.abstractRelationComparision(c, &flag, false);
                    if (v) {
                        a=v;
                        goto Lthrow;
                    }

                    if (flag.isUndefined) {
                        a.putVboolean(false);
                    } else {
                        a.putVboolean(flag == 1);
                    }
                    code += 4;
                    break;
                case IRcge:         // a = (b >=  c)
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    Value flag;
                    v=b.abstractRelationComparision(c, &flag, false);
                    if (v) {
                        a=v;
                        goto Lthrow;
                    }
                    if (flag.isUndefined) {
                        a.putVboolean(false);
                    } else {
                        a.putVboolean(flag != -1);
                    }
                    code += 4;
                    break;

                case IRceq:         // a = (b ==  c)
                case IRcne:         // a = (b !=  c)
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    Lagain:
                    tx = b.getType();
                    ty = c.getType();
                    if(logflag)
                        writef("tx('%s', '%s')\n", tx, ty);
                    if(tx == ty)
                    {
                        if(tx == TypeUndefined ||
                           tx == TypeNull)
                            res = true;
                        else if(tx == TypeNumber)
                        {
                            d_number x = b.number;
                            d_number y = c.number;

                            res = (x == y);
                            //writef("x = %g, y = %g, res = %d\n", x, y, res);
                        }
                        else if(tx == TypeString)
                        {
                            if(logflag)
                            {
                                writef("b = %x, c = %x\n", b, c);
                                writef("cmp('%s', '%s')\n", b.string, c.string);
                                writef("cmp(%d, %d)\n", b.string.length, c.string.length);
                            }
                            res = (b.string == c.string);
                        }
                        else if(tx == TypeBoolean)
                            res = (b.dbool == c.dbool);
                        else // TypeObject
                        {
                            res = b.object == c.object;
                        }
                    }
                    else if(tx == TypeNull && ty == TypeUndefined)
                        res = true;
                    else if(tx == TypeUndefined && ty == TypeNull)
                        res = true;
                    else if(tx == TypeNumber && ty == TypeString)
                    {
                        c.putVnumber(c.toNumber());
                        goto Lagain;
                    }
                    else if(tx == TypeString && ty == TypeNumber)
                    {
                        b.putVnumber(b.toNumber());
                        goto Lagain;
                    }
                    else if(tx == TypeBoolean)
                    {
                        b.putVnumber(b.toNumber());
                        goto Lagain;
                    }
                    else if(ty == TypeBoolean)
                    {
                        c.putVnumber(c.toNumber());
                        goto Lagain;
                    }
                    else if(ty == TypeObject)
                    {
                        v = c.toPrimitive(c, null);
                        if (v) {
                            a = v;
                            goto Lthrow;
                        }
                        goto Lagain;
                    }
                    else if(tx == TypeObject)
                    {
                        v = b.toPrimitive(b, null);
                        if (v) {
                            a = v;
                            goto Lthrow;
                        }
                        goto Lagain;
                    }
                    else
                    {
                        res = false;
                    }

                    res ^= (code.opcode == IRcne);
                    //Lceq:
                    a.putVboolean(res);
                    code += 4;
                    break;

                case IRcid:         // a = (b === c)
                case IRcnid:        // a = (b !== c)
                    a = GETa(code);
                    b = GETb(code);
                    c = GETc(code);
                    // std.stdio.writefln("%s === %s",b.toInfo,c.toInfo);
                    if (cc.isStrictMode && b.isObject && c.isPrimitive) {
                        Value selfval;
                        if (b.isString) {
                            v=b.object.DefaultValue(&selfval, TypeString);
                        } else {
                            v=b.object.DefaultValue(&selfval, TypeNumber);
                        }
                        if (v) {
                            a=v;
                            cc.code=code;
                            goto Lthrow;
                        }

                        res = selfval.identical(c);
                        //  std.stdio.writefln("selfval %s === %s res=%s",selfval.toInfo,c.toInfo, res);
                    } else {
                        res = b.identical(c); // b === c
                    }
                    res ^= (code.opcode == IRcnid);
                    a.putVboolean(res);
                    code += 4;
                    break;

                case IRjt:          // if (b) goto t
                    b = GETb(code);
                    if(b.toBoolean())
                        code += (code + 1).offset;
                    else
                        code += 3;
                    break;

                case IRjf:          // if (!b) goto t
                    b = GETb(code);
                    if(!b.toBoolean())
                        code += (code + 1).offset;
                    else
                        code += 3;
                    break;

                case IRjtb:         // if (b) goto t
                    b = GETb(code);
                    if(b.dbool)
                        code += (code + 1).offset;
                    else
                        code += 3;
                    break;

                case IRjfb:         // if (!b) goto t
                    b = GETb(code);
                    if(!b.dbool)
                        code += (code + 1).offset;
                    else
                        code += 3;
                    break;

                case IRjmp:
                    code += (code + 1).offset;
                    break;

                case IRjlt:         // if (b <   c) goto c
                    b = GETb(code);
                    c = GETc(code);
                    if(b.isNumber() && c.isNumber())
                    {
                        if(b.number < c.number)
                            code += 4;
                        else
                            code += (code + 1).offset;
                        break;
                    }
                    else {
                        v=b.toPrimitive(b, TypeNumber);
                        if (v) {
                            a=v;
                            goto Lthrow;
                        }
                        v=c.toPrimitive(c, TypeNumber);
                        if (v) {
                            a=v;
                            goto Lthrow;
                        }
                        if(b.isString() && c.isString())
                        {
                            d_string x = b.toText;
                            d_string y = c.toText;

                            res = std.string.cmp(x, y) < 0;
                        }
                        else
                            res = b.toNumber() < c.toNumber();
                    }
                    if(!res)
                        code += (code + 1).offset;
                    else
                        code += 4;
                    break;

                case IRjle:         // if (b <=  c) goto c
                    b = GETb(code);
                    c = GETc(code);
                    if(b.isNumber() && c.isNumber())
                    {
                        if(b.number <= c.number)
                            code += 4;
                        else
                            code += (code + 1).offset;
                        break;
                    }
                    else {
                        v=b.toPrimitive(b, TypeNumber);
                        if (v) {
                            a=v;
                            goto Lthrow;
                        }
                        v=c.toPrimitive(c, TypeNumber);
                        if (v) {
                            a=v;
                            goto Lthrow;
                        }
                        if(b.isString() && c.isString())
                        {
                            d_string x = b.toText;
                            d_string y = c.toText;

                            res = std.string.cmp(x, y) <= 0;
                        }
                        else
                            res = b.toNumber() <= c.toNumber();
                    }
                    if(!res)
                        code += (code + 1).offset;
                    else
                        code += 4;
                    break;

                case IRjltc:        // if (b < constant) goto c
                    b = GETb(code);
                    res = (b.toNumber() < *cast(d_number *)(code + 3));
					auto before=code;
                    if(!res) {
                        code += (code + 1).offset;
                    } else {
					  version(D_LP64) {
                        code += 4;
					  } else {
                        code += 5;
					  }
					}
                    break;

                case IRjlec:        // if (b <= constant) goto c
                    b = GETb(code);
					version(D_LP64)
					  res = (b.toNumber() <= (code + 3).number);
					else
					  res = (b.toNumber() <= *cast(d_number *)(code + 3));
                    if(!res)
                        code += (code + 1).offset;
                    else
					  version(D_LP64)
                        code += 4;
					  else
                        code += 5;
                    break;

                case IRiter:                // a = iter(b)
                    a = GETa(code);
                    b = GETb(code);
                    Darray array;
                    //                   writeln("b=",b.toText);
                    if ( b.isUndefined || b.isNull) {
                        owork = new Darray();
                    } else if ( b.isNumber ) {
                        array=new Darray( );
                        array.Put( "0", b.toNumber, 0);
                        owork = array;
                    } else if ( b.isObject ) {
                        owork = b.toObject();
                        Dfunction func;
                        if ( ( func=cast(Dfunction)owork ) !is null ) {
                             array=new Darray();
                             array.Put(func.name, owork, DontEnum);
                             owork=array;
                        }
                    } else {
                        owork = b.toObject();

                    }
                    if(!owork)
                    {
                        a = cannotConvert(b, code.linenum);
                        goto Lthrow;
                    }
                    a = owork.putIterator(a);
                    if(a)
                        goto Lthrow;
                    code += 3;
                    break;

                case IRnext:        // a, b.c, iter
                                    // if (!(b.c = iter)) goto a; iter = iter.next
                    s = GETc(code).toText;
                    goto case_next;

                case IRnexts:       // a, b.s, iter
                    s = (code + 3).id.toText;
                    case_next:
                    iter = GETd(code).iter;
                    v = iter.next();
                    if(!v)
                        code += (code + 1).offset;
                    else
                    {
                        b = GETb(code);
                        b.Put(s, v);
                        code += 5;
                    }
                    break;

                case IRnextscope:   // a, s, iter
                    s = (code + 2).id.toText;
                    iter = GETc(code).iter;
                    v = iter.next();
                    if(!v)
                        code += (code + 1).offset;
                    else
                    {
                        owork = scope_tos(scopex);
                        owork.Put(s, v, 0);
                        code += 4;
                    }
                    break;

                case IRcall:        // a = b.c(argc, argv)
                    s = GETc(code).toText;
                    goto case_call;

                case IRcalls:       // a = b.s(argc, argv)
                    s = (code + 3).id.toText;
                    goto case_call;

                    case_call:
                    a = GETa(code);
                    b = GETb(code);
                    if ( b.isUndefinedOrNull ) {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                            errmsgtbl[ERR_INVALID_OBJECT],b.toText);
                        goto Lthrow;
                     }
                    owork = b.toObject();
                    if(!owork)
                    {
                        goto Lcallerror;
                    }
                    {
					  //writef("v.call\n");
                        v = owork.Get(s);
                        if(!v)
                            goto Lcallerror;
                        //writef("calling... '%s'\n", v.toText);
                        cc.callerothis = othis;
                        a.putVundefined();
						// auto args=GETe(code)[0 .. (code + 4).index];
						// writefln("index=%d",(code + 4).index);
						// foreach(i,a;args) {
						//   writefln("%d) arg=%s",i,a);
						// }
                        a = v.Call(cc, owork, a, GETe(code)[0 .. (code + 4).index]);
                        //writef("regular call, a = %x\n", a);
                    }
                    debug(VERIFY)
                        assert(checksum == IR.verify(__LINE__, codestart));
                    if(a)
                        goto Lthrow;
                    code += 6;
                    goto Lnext;

                    Lcallerror:
                    {
                        //writef("%s %s.%s is undefined and has no Call method\n", b.getType(), b.toText, s);
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_UNDEFINED_NO_CALL3],
                                                 b.getType(), b.toText,
                                                 s);
                        goto Lthrow;
                    }

                case IRcallscope: {   // a = s(argc, argv)
                    id = (code + 2).id;
                    //  s = id.toText;
                    a = GETa(code);
                    v = scope_get_lambda(scopex, id, owork);
                    //std.stdio.writefln("IRcallscope '%s' %x", id.toText, cast(void*)owork);
                    //writefln("v.toText = '%s'", v.toText);
                    if(!v)
                    {
                        a = Dobject.ReferenceError(cc.errorInfo(code), errmsgtbl[ERR_UNDEFINED_VAR],id.toText);
                        //a = Dobject.RuntimeError(&errinfo, errmsgtbl[ERR_UNDEFINED_NO_CALL2], "property", s);
                        goto Lthrow;
                    }
                    // Should we pass othis or o? I think othis.
                    cc.callerothis = othis;        // pass othis to eval()
                    a.putVundefined();
                    // if ( v.isObject && v.object.isStrictMode ) {
                    //     Dobject isolatedo=new ValueObject(null, &Value.vundefined, TEXT_undefined);
                    //     std.stdio.writefln("Isolated object %x",cast(void*)isolatedo);
                    //     a = v.Call(cc, isolatedo, a, GETd(code)[0 .. (code + 3).index]);

                    // } else {

                    if ( v.isObject ) {
                        if (v.object.isStrictMode ) {
                            owork=new ValueObject(null, &Value.vundefined, TEXT_undefined);
//                        } else if ( (othis is cc.global) && !cc.isolated ) {
//                            std.stdio.writefln("othis is global %s ",cc.isolated);
                        } else if (!v.object.isolated) {
                             owork=cc.global;
                        }

                    }
                    a = v.Call(cc, owork, a, GETd(code)[0 .. (code + 3).index]);
                    // }
                    //writef("callscope result = %x\n", a);
                    debug(VERIFY)
                        assert(checksum == IR.verify(__LINE__, codestart));
                    if(a)
                        goto Lthrow;
                    code += 5;
                    goto Lnext;
                }
                case IRcallv:   // v(argc, argv) = a
                    a = GETa(code);
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                    {
                        //writef("%s %s is undefined and has no Call method\n", b.getType(), b.toText);
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_UNDEFINED_NO_CALL2],
                                                 b.getType(), b.toText);
                        goto Lthrow;
                    }
                    if ( a.isNull ) {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_NOT_AN_OBJECT],
                                                 TEXT_TypeError, a.getType());
                        goto Lthrow;
                    }
                    cc.callerothis = othis;        // pass othis to eval()
                    a.putVundefined();
                    a = owork.Call(cc, owork, a, GETd(code)[0 .. (code + 3).index]);
                    if(a)
                        goto Lthrow;
                    code += 5;
                    goto Lnext;

                case IRputcall:        // b.c(argc, argv) = a
                    s = GETc(code).toText;
                    goto case_putcall;

                case IRputcalls:       //  b.s(argc, argv) = a
                    s = (code + 3).id.toText;
                    goto case_putcall;

                    case_putcall:
                    a = GETa(code);
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                        goto Lcallerror;
                    //v = o.GetLambda(s, Value.calcHash(s));
                    v = owork.Get(s);
                    if(!v)
                        goto Lcallerror;
                    //writef("calling... '%s'\n", v.toText);
                    owork = v.toObject();
                    if(!owork)
                    {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_CANNOT_ASSIGN_TO2],
                                                 b.getType(), s);
                        goto Lthrow;
                    }
                    a = owork.put_Value(a, GETe(code)[0 .. (code + 4).index]);
                    if(a)
                        goto Lthrow;
                    code += 6;
                    goto Lnext;

                case IRputcallscope:   // a = s(argc, argv)
                    id = (code + 2).id;
                    s = id.toText;
                    v = scope_get_lambda(scopex, id, owork);
                    if(!v)
                    {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_UNDEFINED_NO_CALL2],
                                                 "property", s);
                        goto Lthrow;
                    }
                    owork = v.toObject();
                    if(!owork)
                    {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_CANNOT_ASSIGN_TO],
                                                 s);
                        goto Lthrow;
                    }
                    a = owork.put_Value(GETa(code), GETd(code)[0 .. (code + 3).index]);
                    if(a)
                        goto Lthrow;
                    code += 5;
                    goto Lnext;

                case IRputcallv:        // b(argc, argv) = a
                    b = GETb(code);
                    owork = b.toObject();
                    if(!owork)
                    {
                        a = Dobject.RuntimeError(cc.errorInfo(code),
                                                 errmsgtbl[ERR_UNDEFINED_NO_CALL2],
                                                 b.getType(), b.toText);
                        goto Lthrow;
                    }
                    a = owork.put_Value(GETa(code), GETd(code)[0 .. (code + 3).index]);
                    if(a)
                        goto Lthrow;
                    code += 5;
                    goto Lnext;

                case IRnew: // a = new b(argc, argv)
                    a = GETa(code);
                    b = GETb(code);
                    a.putVundefined();
                    a=b.Construct(cc, a, GETd(code)[0 .. (code + 3).index]);
                    debug(VERIFY)
                        assert(checksum == IR.verify(__LINE__, codestart));
                    if(a) {
                        goto Lthrow;
                    }
                    code += 5;
                    goto Lnext;

                case IRpush:
                    SCOPECACHE_CLEAR();
                    a = GETa(code);
                    owork = a.toObject();
                    if(!owork || a.isUndefined || a.isNull)
                    {
                        a = cannotConvert(a, code.linenum);
                        goto Lthrow;
                    }
                    scopex ~= owork;                // push entry onto scope chain
                    cc.scopex = scopex;
                    code += 2;
                    break;

                case IRpop:
                    SCOPECACHE_CLEAR();
                    owork = scopex[$ - 1];
                    scopex = scopex[0 .. $ - 1];        // pop entry off scope chain
                    cc.scopex = scopex;
                    // If it's a Finally, we need to execute
                    // the finally block
                    code += 1;

                    if(owork.isFinally())   // test could be eliminated with virtual func
                    {
                        f = cast(Finally)owork;
                        callFinally(f);
                        debug(VERIFY)
                            assert(checksum == IR.verify(__LINE__, codestart));
                    }

                    goto Lnext;

                case IRfinallyret:
                    assert(finallyStack.length);
                    code = finallyStack[$-1];
                    finallyStack = finallyStack[0..$-1];
                    goto Lnext;
                case IRret:
                    version(SCOPECACHE_LOG)
                        printf("scopecache_cnt = %d\n", scopecache_cnt);
                    return null;

                case IRretexp:
                    a = GETa(code);
                    a.checkReference();
                    Value.copy(ret, a);
                    //writef("returns: %s\n", ret.toText);
                    return null;

                case IRimpret:
                    a = GETa(code);
                    a.checkReference();
                    Value.copy(ret, a);
                    //writef("implicit return: %s\n", ret.toText);
                    code += 2;
                    goto Lnext;

                case IRthrow:
                    a = GETa(code);
                    Lthrow:
                    cc.code = code;
                    assert(scopex[0] !is null);
                    v = unwindStack(a);
                    if(v)
                        return v;
                    break;
                case IRtrycatch:
                    SCOPECACHE_CLEAR();
                    offset = ((code - codestart) + (code + 1).offset);
                    s = (code + 2).id.toText;
                    ca = new Catch(offset, s);
                    scopex ~= ca;
                    cc.scopex = scopex;
                    code += 3;
                    break;

                case IRtryfinally:
                    SCOPECACHE_CLEAR();
                    f = new Finally(code + (code + 1).offset);
                    scopex ~= f;
                    cc.scopex = scopex;
                    code += 2;
                    break;

                case IRassert:
                {
                    ErrInfo errinfo=cc.errorInfo;
                    errinfo.linnum = cast(Loc)((code + 1).index);
                    version(all)  // Not supported under some com servers
                    {
                        a = Dobject.RuntimeError(errinfo, errmsgtbl[ERR_ASSERT], (code + 1).index);
                        goto Lthrow;
                    }
                    else
                    {
                        RuntimeErrorx(ERR_ASSERT, (code + 1).index);
                        code += 2;
                        break;
                    }
                }
                case IRuse_strict:
                    // Set strict mode active if it isn't already active
                    IR.strict_cmd=cast(uint)(code+1).index;
                    switch (IR.strict_cmd) {
                    case 1: // on;
                        //std.stdio.writeln("# On");
                        //cc.strict_mode=true;
                        break;
                    case 0: // off
                        //std.stdio.writeln("# Off");
                        //cc.strict_mode=false;
                        break;
                    case 2: // clear and store
//                        store_use_strict_level=cc.use_strict_depth;
                        //                      cc.use_strict_depth=0;
                        //std.stdio.writeln("# Clear");
                        break;
                    case 3: // Restore strict mode
                        // cc.use_strict_depth=store_use_strict_level;
                        //std.stdio.writefln("# Restore %s",(cc.use_strict_depth)?"off":"on");

                        break;
                    default:
                        // unknow 'use strict' code
                    }
                    code += 2;
                    break;
                case IRuse_trace:
                     // Trace flag on/off

                    IR.trace=(code+1).boolean;
                    writeln("trace ",(IR.trace)?"on":"off");
                    code += 2;
                    break;
                }
            }
            catch(ErrorValue err)
            {
                v = unwindStack(&err.value);
                if(v) //v is exception that was not caught
                    return v;
            }
        }

        Linterrupt:
        ret.putVundefined();
        return null;
    }

    /*******************************************
     * This is a 'disassembler' for our interpreted code.
     * Useful for debugging.
     */

    static void print(uint address, IR *code)
    {
        with(IRcode) switch(code.opcode)
        {
        case IRerror:
            writef("\tIRerror\n");
            break;

        case IRnop:
            writef("\tIRnop\n");
            break;

        case IRend:
            writef("\tIRend\n");
            break;

        case IRget:                 // a = b.c
            writef("\tIRget       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRput:                 // b.c = a
            writef("\tIRput       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRgets:                // a = b.s
            writef("\tIRgets      %d, %d, '%s'\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRgetscope:            // a = othis.ident
            writef("\tIRgetscope  %d, '%s', hash=%x\n", (code + 1).index, (code + 2).id.toText, (code + 2).id.toHash);
            break;

        case IRaddass:              // b.c += a
            writef("\tIRaddass    %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRaddasss:             // b.s += a
            writef("\tIRaddasss   %d, %d, '%s'\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRaddassscope:         // othis.ident += a
            writef("\tIRaddassscope  %d, '%s', hash=%x\n", (code + 1).index, (code + 2).id.toText, (code + 3).index);
            break;

        case IRputs:                // b.s = a
            writef("\tIRputs      %d, %d, '%s'\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRputSet:                // b { set s a }
            writef("\tIRputSet    %d, %d, '%s'\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRputGet:                // b { get s a }
            writef("\tIRputGet    %d, %d, '%s'\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRputscope:            // s = a
            writef("\tIRputscope  %d, '%s'\n", (code + 1).index, (code + 2).id.toText);
            break;

        case IRputdefault:                // b = a
            writef("\tIRputdefault %d, %d\n", (code + 1).index, (code + 2).index);
            break;

        case IRputthis:             // b = s
            writef("\tIRputthis   '%s', %d\n", (code + 2).id.toText, (code + 1).index);
            break;

        case IRmov:                 // a = b
            writef("\tIRmov       %d, %d\n", (code + 1).index, (code + 2).index);
            break;

        case IRstring:              // a = "string"
            writef("\tIRstring    %d, '%s'\n", (code + 1).index, (code + 2).id.toText);
            break;

        case IRobject:              // a = object
            auto fd=cast(FunctionDefinition)((code + 2).object);
            writef("\tIRobject    %d, %x :: code=%x\n", (code + 1).index, cast(void*)(code + 2).object, cast(void*)((fd)?fd.code:null));
            break;

        case IRthis:                // a = this
            writef("\tIRthis      %d\n", (code + 1).index);
            break;

        case IRnumber:              // a = number
		  version(D_LP64)
            writef("\tIRnumber    %d, %g\n", (code + 1).index, (code + 2).number);
		  else
            writef("\tIRnumber    %d, %g\n", (code + 1).index, *cast(d_number *)(code + 2));
            break;

        case IRboolean:             // a = boolean
            writef("\tIRboolean   %d, %d\n", (code + 1).index, (code + 2).boolean);
            break;

        case IRnull:                // a = null
            writef("\tIRnull      %d\n", (code + 1).index);
            break;

        case IRundefined:           // a = undefined
            writef("\tIRundefined %d\n", (code + 1).index);
            break;

        case IRthisget:             // a = othis.ident
            writef("\tIRthisget   %d, '%s'\n", (code + 1).index, (code + 2).id.toText);
            break;

        case IRneg:                 // a = -a
            writef("\tIRneg      %d\n", (code + 1).index);
            break;

        case IRpos:                 // a = a
            writef("\tIRpos      %d\n", (code + 1).index);
            break;

        case IRcom:                 // a = ~a
            writef("\tIRcom      %d\n", (code + 1).index);
            break;

        case IRnot:                 // a = !a
            writef("\tIRnot      %d\n", (code + 1).index);
            break;

        case IRtypeof:              // a = typeof a
            writef("\tIRtypeof   %d\n", (code + 1).index);
            break;

        case IRinstance:            // a = b instanceof c
            writef("\tIRinstance  %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRadd:                 // a = b + c
            writef("\tIRadd       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRsub:                 // a = b - c
            writef("\tIRsub       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRmul:                 // a = b * c
            writef("\tIRmul       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRdiv:                 // a = b / c
            writef("\tIRdiv       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRmod:                 // a = b % c
            writef("\tIRmod       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRshl:                 // a = b << c
            writef("\tIRshl       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRshr:                 // a = b >> c
            writef("\tIRshr       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRushr:                // a = b >>> c
            writef("\tIRushr      %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRand:                 // a = b & c
            writef("\tIRand       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRor:                  // a = b | c
            writef("\tIRor        %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRxor:                 // a = b ^ c
            writef("\tIRxor       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRin:                 // a = b in c
            writef("\tIRin        %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRpreinc:                  // a = ++b.c
            writef("\tIRpreinc  %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRpreincs:            // a = ++b.s
            writef("\tIRpreincs %d, %d, %s\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRpreincscope:        // a = ++s
            writef("\tIRpreincscope %d, '%s', hash=%x\n", (code + 1).index, (code + 2).id.toText, (code + 3).hash);
            break;

        case IRpredec:             // a = --b.c
            writef("\tIRpredec  %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRpredecs:            // a = --b.s
            writef("\tIRpredecs %d, %d, %s\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRpredecscope:        // a = --s
            writef("\tIRpredecscope %d, '%s', hash=%x\n", (code + 1).index, (code + 2).id.toText, (code + 3).hash);
            break;

        case IRpostinc:     // a = b.c++
            writef("\tIRpostinc  %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRpostincs:            // a = b.s++
            writef("\tIRpostincs %d, %d, %s\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRpostincscope:        // a = s++
            writef("\tIRpostincscope %d, %s\n", (code + 1).index, (code + 2).id.toText);
            break;

        case IRpostdec:             // a = b.c--
            writef("\tIRpostdec  %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRpostdecs:            // a = b.s--
            writef("\tIRpostdecs %d, %d, %s\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRpostdecscope:        // a = s--
            writef("\tIRpostdecscope %d, %s\n", (code + 1).index, (code + 2).id.toText);
            break;

        case IRdel:                 // a = delete b.c
            writef("\tIRdel       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRdels:                // a = delete b.s
            writef("\tIRdels      %d, %d, '%s'\n", (code + 1).index, (code + 2).index, (code + 3).id.toText);
            break;

        case IRdelscope:            // a = delete s
            writef("\tIRdelscope  %d, '%s'\n", (code + 1).index, (code + 2).id.toText);
            break;

        case IRclt:                 // a = (b <   c)
            writef("\tIRclt       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRcle:                 // a = (b <=  c)
            writef("\tIRcle       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRcgt:                 // a = (b >   c)
            writef("\tIRcgt       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRcge:                 // a = (b >=  c)
            writef("\tIRcge       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRceq:                 // a = (b ==  c)
            writef("\tIRceq       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRcne:                 // a = (b !=  c)
            writef("\tIRcne       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRcid:                 // a = (b === c)
            writef("\tIRcid       %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRcnid:        // a = (b !== c)
            writef("\tIRcnid      %d, %d, %d\n", (code + 1).index, (code + 2).index, (code + 3).index);
            break;

        case IRjt:                  // if (b) goto t
            writef("\tIRjt        %d, %d\n", (code + 1).index + address, (code + 2).index);
            break;

        case IRjf:                  // if (!b) goto t
            writef("\tIRjf        %d, %d\n", (code + 1).index + address, (code + 2).index);
            break;

        case IRjtb:                 // if (b) goto t
            writef("\tIRjtb       %d, %d\n", (code + 1).index + address, (code + 2).index);
            break;

        case IRjfb:                 // if (!b) goto t
            writef("\tIRjfb       %d, %d\n", (code + 1).index + address, (code + 2).index);
            break;

        case IRjmp:
            writef("\tIRjmp       %d\n", (code + 1).offset + address);
            break;

        case IRjlt:                 // if (b < c) goto t
            writef("\tIRjlt       %d, %d, %d\n", (code + 1).index + address, (code + 2).index, (code + 3).index);
            break;

        case IRjle:                 // if (b <= c) goto t
            writef("\tIRjle       %d, %d, %d\n", (code + 1).index + address, (code + 2).index, (code + 3).index);
            break;

        case IRjltc:                // if (b < constant) goto t
            writef("\tIRjltc      %d, %d, %g\n", (code + 1).index + address, (code + 2).index, *cast(d_number *)(code + 3));
            break;

        case IRjlec:                // if (b <= constant) goto t
            writef("\tIRjlec      %d, %d, %g\n", (code + 1).index + address, (code + 2).index, *cast(d_number *)(code + 3));
            break;

        case IRiter:                // a = iter(b)
            writef("\tIRiter    %d, %d\n", (code + 1).index, (code + 2).index);
            break;

        case IRnext:                // a, b.c, iter
            writef("\tIRnext    %d, %d, %d, %d\n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).index,
                   (code + 4).index);
            break;

        case IRnexts:               // a, b.s, iter
            writef("\tIRnexts   %d, %d, '%s', %d\n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).id.toText,
                   (code + 4).index);
            break;

        case IRnextscope:           // a, s, iter
            writef
                ("\tIRnextscope   %d, '%s', %d\n",
                (code + 1).index,
                (code + 2).id.toText,
                (code + 3).index);
            break;

        case IRcall:                // a = b.c(argc, argv)
            writef("\tIRcall     %d,%d,%d, argc=%d, argv=%d \n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).index,
                   (code + 4).index,
                   (code + 5).index);
            break;

        case IRcalls:               // a = b.s(argc, argv)
            writef
                ("\tIRcalls     %d,%d,'%s', argc=%d, argv=%d \n",
                (code + 1).index,
                (code + 2).index,
                (code + 3).id.toText,
                (code + 4).index,
                (code + 5).index);
            break;

        case IRcallscope:           // a = s(argc, argv)
            writef
                ("\tIRcallscope %d,'%s', argc=%d, argv=%d \n",
                (code + 1).index,
                (code + 2).id.toText,
                (code + 3).index,
                (code + 4).index);
            break;

        case IRputcall:                // a = b.c(argc, argv)
            writef("\tIRputcall  %d,%d,%d, argc=%d, argv=%d \n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).index,
                   (code + 4).index,
                   (code + 5).index);
            break;

        case IRputcalls:               // a = b.s(argc, argv)
            writef
                ("\tIRputcalls  %d,%d,'%s', argc=%d, argv=%d \n",
                (code + 1).index,
                (code + 2).index,
                (code + 3).id.toText,
                (code + 4).index,
                (code + 5).index);
            break;

        case IRputcallscope:           // a = s(argc, argv)
            writef
                ("\tIRputcallscope %d,'%s', argc=%d, argv=%d \n",
                (code + 1).index,
                (code + 2).id.toText,
                (code + 3).index,
                (code + 4).index);
            break;

        case IRcallv:               // a = v(argc, argv)
            writef("\tIRcallv    %d, %d(argc=%d, argv=%d)\n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).index,
                   (code + 4).index);
            break;

        case IRputcallv:               // a = v(argc, argv)
            writef("\tIRputcallv %d, %d(argc=%d, argv=%d)\n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).index,
                   (code + 4).index);
            break;

        case IRnew:         // a = new b(argc, argv)
            writef("\tIRnew       %d,%d, argc=%d, argv=%d \n",
                   (code + 1).index,
                   (code + 2).index,
                   (code + 3).index,
                   (code + 4).index);
            break;

        case IRpush:
            writef("\tIRpush    %d\n", (code + 1).index);
            break;

        case IRpop:
            writef("\tIRpop\n");
            break;

        case IRret:
            writef("\tIRret\n");
            return;

        case IRretexp:
            writef("\tIRretexp    %d\n", (code + 1).index);
            return;

        case IRimpret:
            writef("\tIRimpret    %d\n", (code + 1).index);
            return;

        case IRthrow:
            writef("\tIRthrow     %d\n", (code + 1).index);
            break;

        case IRassert:
            writef("\tIRassert    %d\n", (code + 1).index);
            break;
		case IRcheckref:
			writef("\tIRcheckref  %d\n",(code+1).index);
			break;
        case IRtrycatch:
            writef("\tIRtrycatch  %d, '%s'\n", (code + 1).offset + address, (code + 2).id.toText);
            break;

        case IRtryfinally:
            writef("\tIRtryfinally %d\n", (code + 1).offset + address);
            break;

        case IRfinallyret:
            writef("\tIRfinallyret\n");
            break;

        case IRuse_strict:
            writef("\tIRuse_strict %s\n", ["off","on","clear","restore"][(code +1).index]);
            break;
        case IRuse_trace:
            writef("\tIRuse_trace %s\n", (code + 1).boolean?"on":"off");
            break;

        default:
            writef("2: Unrecognized IR instruction %d\n", code.opcode);
            assert(0);              // unrecognized IR instruction
        }
    }

    /*********************************
     * Give size of opcode.
     */

    static uint size(IRcode opcode)
    {
        uint sz = 9999;

        with(IRcode) final switch(opcode)
        {
        case IRerror:
        case IRnop:
        case IRend:
            sz = 1;
            break;

        case IRget:                 // a = b.c
        case IRaddass:
            sz = 4;
            break;

        case IRput:                 // b.c = a
            sz = 4;
            break;

        case IRgets:                // a = b.s
        case IRaddasss:
            sz = 4;
            break;

        case IRgetscope:            // a = s
            sz = 3;
            break;

        case IRaddassscope:
            sz = 4;
            break;

        case IRputs:                // b.s = a
        case IRputSet:              // b { set s a }
        case IRputGet:              // b { get s a }

            sz = 4;
            break;

        case IRputscope:        // s = a
        case IRputdefault:      // b = a
            sz = 3;
            break;

        case IRputthis:             // a = s
            sz = 3;
            break;

        case IRmov:                 // a = b
            sz = 3;
            break;

        case IRstring:              // a = "string"
            sz = 3;
            break;

        case IRobject:              // a = object
            sz = 3;
            break;

        case IRthis:                // a = this
            sz = 2;
            break;

        case IRnumber:              // a = number
            version(D_LP64) {
                static assert(double.sizeof==unsigned.sizeof);
                sz = 3;
            } else {
                sz = 4;
            }
            break;

        case IRboolean:             // a = boolean
            sz = 3;
            break;

        case IRnull:                // a = null
            sz = 2;
            break;

        case IRcheckref:
        case IRundefined:           // a = undefined
            sz = 2;
            break;


        case IRthisget:             // a = othis.ident
            sz = 3;
            break;

        case IRneg:                 // a = -a
        case IRpos:                 // a = a
        case IRcom:                 // a = ~a
        case IRnot:                 // a = !a
        case IRtypeof:              // a = typeof a
            sz = 2;
            break;

        case IRinstance:            // a = b instanceof c
        case IRadd:                 // a = b + c
        case IRsub:                 // a = b - c
        case IRmul:                 // a = b * c
        case IRdiv:                 // a = b / c
        case IRmod:                 // a = b % c
        case IRshl:                 // a = b << c
        case IRshr:                 // a = b >> c
        case IRushr:                // a = b >>> c
        case IRand:                 // a = b & c
        case IRor:                  // a = b | c
        case IRxor:                 // a = b ^ c
        case IRin:                  // a = b in c
            sz = 4;
            break;

        case IRpreinc:             // a = ++b.c
        case IRpreincs:            // a = ++b.s
        case IRpredec:             // a = --b.c
        case IRpredecs:            // a = --b.s
        case IRpostinc:            // a = b.c++
        case IRpostincs:           // a = b.s++
        case IRpostdec:            // a = b.c--
        case IRpostdecs:           // a = b.s--
            sz = 4;
            break;

        case IRpostincscope:        // a = s++
        case IRpostdecscope:        // a = s--
            sz = 3;
            break;

        case IRpreincscope:     // a = ++s
        case IRpredecscope:     // a = --s
            sz = 4;
            break;

        case IRdel:                 // a = delete b.c
        case IRdels:                // a = delete b.s
            sz = 4;
            break;

        case IRdelscope:            // a = delete s
            sz = 3;
            break;

        case IRclt:                 // a = (b <   c)
        case IRcle:                 // a = (b <=  c)
        case IRcgt:                 // a = (b >   c)
        case IRcge:                 // a = (b >=  c)
        case IRceq:                 // a = (b ==  c)
        case IRcne:                 // a = (b !=  c)
        case IRcid:                 // a = (b === c)
        case IRcnid:                // a = (b !== c)
        case IRjlt:                 // if (b < c) goto t
        case IRjle:                 // if (b <= c) goto t
            sz = 4;
            break;

        case IRjltc:                // if (b < constant) goto t
        case IRjlec:                // if (b <= constant) goto t
            version(D_LP64)
                sz = 4;
            else
                sz = 5;
            break;

        case IRjt:                  // if (b) goto t
        case IRjf:                  // if (!b) goto t
        case IRjtb:                 // if (b) goto t
        case IRjfb:                 // if (!b) goto t
            sz = 3;
            break;

        case IRjmp:
            sz = 2;
            break;

        case IRiter:                // a = iter(b)
            sz = 3;
            break;

        case IRnext:                // a, b.c, iter
        case IRnexts:               // a, b.s, iter
            sz = 5;
            break;

        case IRnextscope:           // a, s, iter
            sz = 4;
            break;

        case IRcall:                // a = b.c(argc, argv)
        case IRcalls:               // a = b.s(argc, argv)
        case IRputcall:             //  b.c(argc, argv) = a
        case IRputcalls:            //  b.s(argc, argv) = a
            sz = 6;
            break;

        case IRcallscope:           // a = s(argc, argv)
        case IRputcallscope:        // s(argc, argv) = a
        case IRcallv:
        case IRputcallv:
            sz = 5;
            break;

        case IRnew:                 // a = new b(argc, argv)
            sz = 5;
            break;

        case IRpush:
            sz = 2;
            break;

        case IRpop:
            sz = 1;
            break;

        case IRfinallyret:
        case IRret:
            sz = 1;
            break;

        case IRretexp:
        case IRimpret:
        case IRthrow:
            sz = 2;
            break;

        case IRtrycatch:
            sz = 3;
            break;

        case IRtryfinally:
            sz = 2;
            break;

        case IRassert:
            sz = 2;
            break;

        case IRuse_strict:
            sz = 2;
            break;
        case IRuse_trace:
            sz = 2;
            break;

            version(none) {
        default:
            writef("3: Unrecognized IR instruction %d, IRMAX = %d\n", opcode, IRcode.max);
            assert(0);              // unrecognized IR instruction
            }
        }
        assert(sz <= 6);
        return sz;
    }

    static void printfunc(IR *code)
    {
        IR *codestart = code;
        writefln("# %x",codestart);
        if (!codestart) return;
        for(;; )
        {
            //writef("%2d(%d):", code - codestart, code.linnum);
            writef("%2d:", code - codestart);
            print(cast(uint)(code - codestart), code);
            if(code.opcode == IRcode.IRend)
                return;
            code += size(code.opcode);
        }
    }

    /***************************************
     * Verify that it is a correct sequence of code.
     * Useful for isolating memory corruption bugs.
     */

    static uint verify(uint linnum, IR *codestart)
    {
        debug(VERIFY)
        {
            uint checksum = 0;
            uint sz;
            uint i;
            IR *code;

            // Verify code
            for(code = codestart;; )
            {
                switch(code.opcode)
                {
                case IRend:
                    return checksum;

                case IRerror:
                    writef("verify failure line %u\n", linnum);
                    assert(0);
                    break;

                default:
                    if(code.opcode >= IRMAX)
                    {
                        writef("undefined opcode %d in code %p\n", code.opcode, codestart);
                        assert(0);
                    }
                    sz = IR.size(code.opcode);
                    for(i = 0; i < sz; i++)
                    {
                        checksum += code.opcode;
                        code++;
                    }
                    break;
                }
            }
        }
        else
            return 0;
    }
}
