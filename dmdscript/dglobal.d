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

module dmdscript.dglobal;

import std.uri;
import std.c.stdlib;
import std.c.string;
import std.stdio;
import std.algorithm;
import std.math;
import std.exception;

import dmdscript.script;
import dmdscript.protoerror;
import dmdscript.parse;
import dmdscript.text;
import dmdscript.dobject;
import dmdscript.value;
import dmdscript.statement;
import dmdscript.threadcontext;
import dmdscript.functiondefinition;
import dmdscript.scopex;
import dmdscript.opcodes;
import dmdscript.property;

import dmdscript.dstring;
import dmdscript.darray;
import dmdscript.dregexp;
import dmdscript.dnumber;
import dmdscript.dboolean;
import dmdscript.dfunction;
import dmdscript.dnative;

static if (is(std.uri.URIException)) { //
    // URIerror change name in version 2.065.0
    alias std.uri.URIException URIerror;
}

version(Ecmascript5) {
  import dmdscript.djson;
}

d_string arg0string(Value[] arglist)
{
    Value* v = arglist.length ? &arglist[0] : &Value.vundefined;
    return v.toText;
}

/* ====================== Dglobal_eval ================ */

Value* Dglobal_eval(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.1
    Value* v;
    d_string s;
    FunctionDefinition fd;
    ErrInfo errinfo;
    CallContext* localcc;
    Value *result;
    Value[] locals;
    //FuncLog funclog(L"Global.eval()");
    v = arglist.length ? &arglist[0] : &Value.vundefined;
    if(v.getType() != TypeString)
    {
        Value.copy(ret, v);
        return null;
    }
    auto save_currentcc=CallContext.currentcc;
    auto save_scopex=cc.scopex;
    auto save_script_mode=cc.strict_mode;
//    auto save_iseval = cc.iseval;
    scope(exit) {
         CallContext.currentcc=save_currentcc;
         cc.scopex=save_scopex;
         cc.strict_mode=save_script_mode;
//         cc.iseval=save_iseval;
    }


    s = v.toText;
    if ( Value.check(othis.Get(TEXT_eval_verbose)).toBoolean ) writef("eval('%s')\n", s);

    // Parse program
    TopStatement[] topstatements;
    Parser p = new Parser("eval", s, 0, true);
    // Strict mode of the call context is passed to the eval
    // Ecma 10.4.2.3b
    p.use_strict=cc.isStrictMode;
    p.inside_function_block=true; // Thread eval like a function block
    if(p.parseProgram(topstatements, errinfo))
        goto Lsyntaxerror;

    // Analyze, generate code
    fd = new FunctionDefinition(topstatements);
    fd.iseval = true;
    fd.strict_mode=cc.isStrictMode;
    {
        Scope sc;
        sc.ctor(fd);
        sc.src = s;
        fd.semantic(&sc);
        errinfo = sc.errinfo;
        sc.dtor();
    }
    if(errinfo.message)
        goto Lsyntaxerror;
    fd.toIR(null);

    // Execute code
    // Allocation used for locals
    locals=new Value[fd.nlocals];


    // The scope chain is initialized to contain the same objects,
    // in the same order, as the calling context's scope chain.
    // This includes objects added to the calling context's
    // scope chain by WithStatement.
    //    cc.scopex.reserve(fd.withdepth);

    // Variable instantiation is performed using the calling
    // context's variable object and using empty
    // property attributes
    void setlocal(CallContext* localcc) {
        fd.instantiate(localcc.scopex, localcc.variable, 0);
    }

    // The this value is the same as the this value of the
    // calling context.
    assert(cc.callerothis);


    if ( Value.check(othis.Get(TEXT_eval_verbose)).toBoolean ) {

        dmdscript.opcodes.IR.printfunc(fd.code);
    }

    localcc=cc;
    if (othis is cc.global) {
        // Eval is called directly
        if (p.use_strict) {
//            std.stdio.writeln("Clone context");
            // The context is cloned in strict mode
            localcc=cc.clone;
            //  cc.scopex=CallContext.clone(cc.scopex);
//            std.stdio.writeln("strict mode");
//            cc.scopex=cc.scopex.dup;

        }
        setlocal(localcc);
        localcc.strict_mode=fd.strict_mode;
//        localcc.isolated=true;
        //   localcc.iseval=true;
        result = IR.call(localcc, localcc.callerothis, fd.code, ret, locals.ptr);
    } else {
        // If eval is called indirectly we use a copy of global scope
        if (p.use_strict) {
            localcc=cc.clone;
        } else {
            localcc.scopex=localcc.scopex[0..cc.globalroot].dup;
        }
        setlocal(localcc);
        localcc.strict_mode=fd.strict_mode;
        //  localcc.iseval=true;
        //localcc.isolated=true;
        result = IR.call(localcc, localcc.callerothis, fd.code, ret, locals.ptr);
    }
    fd = null;
    return result;

    Lsyntaxerror:
    Dobject o;

    // For eval()'s, use location of caller, not the string
    // errinfo.linnum = 0;

    ret.putVundefined();
    final switch (errinfo.etype) {
    case error_type_t.syntaxerror: o = new syntaxerror.D0(errinfo); break;
    case error_type_t.referenceerror: o = new referenceerror.D0(errinfo); break;
    case error_type_t.evalerror: o = new evalerror.D0(errinfo); break;
    case error_type_t.rangeerror: o = new rangeerror.D0(errinfo); break;
    case error_type_t.typeerror: o = new typeerror.D0(errinfo); break;
    case error_type_t.urierror: o = new urierror.D0(errinfo); break;
    }

    Value* v2 = new Value;
    v2.putVobject(o);
    return v2;
    assert(0);
}

/* ====================== Dglobal_parseInt ================ */

Value* Dglobal_parseInt(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.2
    Value* v2;
    immutable(wchar)* s;
    immutable(wchar)* z;
    d_int32 radix;
    int sign = 1;
    d_number number;
    uint i;
    d_string string;

    string = arg0string(arglist);

    //writefln("Dglobal_parseInt('%s')", string);

    while(i < string.length)
    {
        size_t idx = i;
        dchar c = std.utf.decode(string, idx);
        if(!isStrWhiteSpaceChar(c))
            break;
        i = cast(uint)idx;
    }
    s = string.ptr + i;
    i = cast(uint)string.length - i; // 64bit cast

    if(i)
    {
        if(*s == '-')
        {
            sign = -1;
            s++;
            i--;
        }
        else if(*s == '+')
        {
            s++;
            i--;
        }
    }

    radix = 0;
    if(arglist.length >= 2)
    {
        v2 = &arglist[1];
        radix = v2.toInt32();
    }

    if(radix)
    {
        if(radix < 2 || radix > 36)
        {
            number = d_number.nan;
            goto Lret;
        }
        if(radix == 16 && i >= 2 && *s == '0' &&
           (s[1] == 'x' || s[1] == 'X'))
        {
            s += 2;
            i -= 2;
        }
    }
    else if(i >= 1 && *s != '0')
    {
        radix = 10;
    }
    else if(i >= 2 && (s[1] == 'x' || s[1] == 'X'))
    {
        radix = 16;
        s += 2;
        i -= 2;
    }
    else
        radix = 8;

    number = 0;
    for(z = s; i; z++, i--)
    {
        d_int32 n;
        wchar c;

        c = *z;
        if('0' <= c && c <= '9')
            n = c - '0';
        else if('A' <= c && c <= 'Z')
            n = c - 'A' + 10;
        else if('a' <= c && c <= 'z')
            n = c - 'a' + 10;
        else
            break;
        if(radix <= n)
            break;
        number = number * radix + n;
    }
    if(z == s)
    {
        number = d_number.nan;
        goto Lret;
    }
    if(sign < 0)
        number = -number;

    version(none)     // ECMA says to silently ignore trailing characters
    {
        while(z - &string[0] < string.length)
        {
            if(!isStrWhiteSpaceChar(*z))
            {
                number = d_number.nan;
                goto Lret;
            }
            z++;
        }
    }

    Lret:
    ret.putVnumber(number);
    return null;
}

/* ====================== Dglobal_parseFloat ================ */

Value* Dglobal_parseFloat(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.3
    d_number n;
    size_t endidx;

    d_string string = arg0string(arglist);
    n = StringNumericLiteral(string, endidx, 1);

    ret.putVnumber(n);
    return null;
}

/* ====================== Dglobal_escape ================ */

int ISURIALNUM(dchar c)
{
    return (c >= 'a' && c <= 'z') ||
           (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9');
}

wchar TOHEX[16 + 1] = "0123456789ABCDEF";

Value* Dglobal_escape(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.4
    d_string s;
    uint escapes;
    uint unicodes;
    size_t slen;

    s = arg0string(arglist);
    escapes = 0;
    unicodes = 0;
    foreach(dchar c; s)
    {
        slen++;
        if(c >= 0x100)
            unicodes++;
        else
        if(c == 0 || c >= 0x80 || (!ISURIALNUM(c) && std.string.indexOf("*@-_+./", c) == -1))
            escapes++;
    }
    if((escapes + unicodes) == 0)
    {
        ret.putVstring(assumeUnique(s));
        return null;
    }
    else
    {
        //writefln("s.length = %d, escapes = %d, unicodes = %d", s.length, escapes, unicodes);
        wchar[] R = new wchar[slen + escapes * 2 + unicodes * 5];
        wchar* r = R.ptr;
        foreach(c; s)
        {
            if(c >= 0x100)
            {
                r[0] = '%';
                r[1] = 'u';
                r[2] = TOHEX[(c >> 12) & 15];
                r[3] = TOHEX[(c >> 8) & 15];
                r[4] = TOHEX[(c >> 4) & 15];
                r[5] = TOHEX[c & 15];
                r += 6;
            }
            else if(c == 0 || c >= 0x80 || (!ISURIALNUM(c) && std.string.indexOf("*@-_+./", c) == -1))
            {
                r[0] = '%';
                r[1] = TOHEX[c >> 4];
                r[2] = TOHEX[c & 15];
                r += 3;
            }
            else
            {
                r[0] = c;
                r++;
            }
        }
        assert(r - R.ptr == R.length);
        ret.putVstring(assumeUnique(R));
        return null;
    }
}

/* ====================== Dglobal_unescape ================ */

Value* Dglobal_unescape(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.5
    d_string s;
    d_string R;

    s = arg0string(arglist);
    //writefln("Dglobal.unescape(s = '%s')", s);
    for(size_t k = 0; k < s.length; k++)
    {
        wchar c = s[k];

        if(c == '%')
        {
            if(k + 6 <= s.length && s[k + 1] == 'u')
            {
                uint u;

                u = 0;
                for(int i = 2;; i++)
                {
                    uint x;

                    if(i == 6)
                    {
                        R~=cast(wchar)u;
                        // dmdscript.utf.encode(R, cast(dchar)u);
                        k += 5;
                        goto L1;
                    }
                    x = s[k + i];
                    if('0' <= x && x <= '9')
                        x = x - '0';
                    else if('A' <= x && x <= 'F')
                        x = x - 'A' + 10;
                    else if('a' <= x && x <= 'f')
                        x = x - 'a' + 10;
                    else
                        break;
                    u = (u << 4) + x;
                }
            }
            else if(k + 3 <= s.length)
            {
                uint u;

                u = 0;
                for(int i = 1;; i++)
                {
                    uint x;
                    if(i == 3)
                    {
                        R~=cast(wchar)u;
                        //   dmdscript.utf.encode(R, cast(dchar)u);
                        k += 2;
                        goto L1;
                    }
                    x = s[k + i];
                    if('0' <= x && x <= '9')
                        x = x - '0';
                    else if('A' <= x && x <= 'F')
                        x = x - 'A' + 10;
                    else if('a' <= x && x <= 'f')
                        x = x - 'a' + 10;
                    else
                        break;
                    u = (u << 4) + x;
                }
            }
        }
        R ~= c;
        L1:
        ;
    }

    ret.putVstring(R);
    return null;
}

/* ====================== Dglobal_isNaN ================ */

Value* Dglobal_isNaN(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.6
    Value* v;
    d_number n;
    d_boolean b;

    if(arglist.length)
        v = &arglist[0];
    else
        v = &Value.vundefined;
    n = v.toNumber();
    b = isNaN(n) ? true : false;
    ret.putVboolean(b);
    return null;
}

/* ====================== Dglobal_isFinite ================ */

Value* Dglobal_isFinite(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA 15.1.2.7
    Value* v;
    d_number n;
    d_boolean b;

    if(arglist.length)
        v = &arglist[0];
    else
        v = &Value.vundefined;
    n = v.toNumber();
    b = isFinite(n) ? true : false;
    ret.putVboolean(b);
    return null;
}

/* ====================== Dglobal_ URI Functions ================ */

Value* URI_error(d_string s)
{
    Dobject o = new urierror.D0(s ~ "() failure");
    Value* v = new Value;
    v.putVobject(o);
    return v;
}

Value* Dglobal_decodeURI(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA v3 15.1.3.1
    d_string s;

    s = arg0string(arglist);
    try
    {
        immutable(char)[] suri;
        // from utf16 to utf8
        suri=dmdscript.script.fromDstring(s);
        suri = std.uri.decode(suri);
        // And back again
        s=dmdscript.script.toDstring(suri);
    }
    catch(URIerror u)
    {
        ret.putVundefined();
        return URI_error(TEXT_decodeURI);
    }
    ret.putVstring(s);
    return null;
}

Value* Dglobal_decodeURIComponent(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA v3 15.1.3.2
    d_string s;

    s = arg0string(arglist);
    try
    {
       immutable(char)[] suri;
       // from utf16 to utf8
       suri=dmdscript.script.fromDstring(s);
       suri = std.uri.decodeComponent(suri);
       // And back again
       s=dmdscript.script.toDstring(suri);
    }
    catch(URIerror u)
    {
        ret.putVundefined();
        return URI_error(TEXT_decodeURIComponent);
    }
    ret.putVstring(s);
    return null;
}

Value* Dglobal_encodeURI(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA v3 15.1.3.3
    d_string s;

    s = arg0string(arglist);
    try
    {
        immutable(char)[] suri;
        // from utf16 to utf8
        suri=dmdscript.script.fromDstring(s);
        suri = std.uri.encode(suri);
        // And back again
        s=dmdscript.script.toDstring(suri);
     }
    catch(URIerror u)
    {
        ret.putVundefined();
        return URI_error(TEXT_encodeURI);
    }
    ret.putVstring(s);
    return null;
}

Value* Dglobal_encodeURIComponent(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // ECMA v3 15.1.3.4
    d_string s;

    s = arg0string(arglist);
    try
    {
        immutable(char)[] suri;
        // from utf16 to utf8
        suri=dmdscript.script.fromDstring(s);
        suri = std.uri.encodeComponent(suri);
        // And back again
        s=dmdscript.script.toDstring(suri);
    }
    catch(URIerror u)
    {
        ret.putVundefined();
        return URI_error(TEXT_encodeURIComponent);
    }
    ret.putVstring(s);
    return null;
}

/* ====================== Dglobal_print ================ */

static void dglobal_print(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // Our own extension
    if(arglist.length)
    {
        uint i;

        for(i = 0; i < arglist.length; i++)
        {
            d_string s = arglist[i].toText();

            writef("%s", s);
        }
    }

    ret.putVundefined();
}

Value* Dglobal_print(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // Our own extension
    dglobal_print(cc, othis, ret, arglist);
    return null;
}

/* ====================== Dglobal_println ================ */

Value* Dglobal_println(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // Our own extension
    dglobal_print(cc, othis, ret, arglist);
    writef("\n");
    return null;
}

/* ====================== Dglobal_readln ================ */

Value* Dglobal_readln(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // Our own extension
    int c;
    d_string s;

    for(;; )
    {
        version(linux)
        {
            c = std.c.stdio.getchar();
            if(c == EOF)
                break;
        }
        else version(Windows)
        {
            c = std.c.stdio.getchar();
            if(c == EOF)
                break;
        }
        else version(OSX)
        {
            c = std.c.stdio.getchar();
            if(c == EOF)
                break;
        }
        else version(FreeBSD)
        {
            c = std.c.stdio.getchar();
            if(c == EOF)
                break;
        }
        else
        {
            static assert(0);
        }
        if(c == '\n')
            break;
        s~=cast(wchar)c;
    }
    ret.putVstring(s);
    return null;
}

/* ====================== Dglobal_getenv ================ */

Value* Dglobal_getenv(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    // Our own extension
    ret.putVundefined();
    if(arglist.length)
    {
        d_string s = arglist[0].toText();
        immutable(char)[] senv;
        foreach(c;s) {
            char[4] buf;
            senv~=std.utf.toUTF8(buf,c);
        }
        char* p = getenv(std.string.toStringz(senv));
        if(p)
            ret.putVstring(p[0 .. strlen(p)].idup);
        else
            ret.putVnull();
    }
    return null;
}


/* ====================== Dglobal_ScriptEngine ================ */

Value* Dglobal_ScriptEngine(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    ret.putVstring(TEXT_DMDScript);
    return null;
}

Value* Dglobal_ScriptEngineBuildVersion(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    ret.putVnumber(BUILD_VERSION);
    return null;
}

Value* Dglobal_ScriptEngineMajorVersion(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    ret.putVnumber(MAJOR_VERSION);
    return null;
}

Value* Dglobal_ScriptEngineMinorVersion(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    ret.putVnumber(MINOR_VERSION);
    return null;
}


Value* Dglobal_isStrictMode(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    *ret=cc.isStrictMode;
    return null;
}

/* ====================== Dglobal =========================== */

class Dglobal : Dobject
{
    this(wchar[][] argv)
    {
        super(Dobject.getPrototype());  // Dglobal.prototype is implementation-dependent

        //writef("Dglobal.Dglobal(%x)\n", this);

        Dobject f = Dfunction.getPrototype();

        classname = TEXT_global;

        // ECMA 15.1
        // Add in built-in objects which have attribute { DontEnum }

        // Value properties
        Put(TEXT_NaN, d_number.nan, DontEnum | DontDelete | DontConfig | ReadOnly);
        Put(TEXT_Infinity, d_number.infinity, DontEnum | DontDelete | DontConfig | ReadOnly);
        Put(TEXT_undefined, &Value.vundefined, DontEnum | DontDelete | DontConfig | ReadOnly);
        static enum NativeFunctionData nfd[] =
        [
            // Function properties
            { TEXT_eval, &Dglobal_eval, 1 },
            { TEXT_parseInt, &Dglobal_parseInt, 2 },
            { TEXT_parseFloat, &Dglobal_parseFloat, 1 },
            { TEXT_escape, &Dglobal_escape, 1 },
            { TEXT_unescape, &Dglobal_unescape, 1 },
            { TEXT_isNaN, &Dglobal_isNaN, 1 },
            { TEXT_isFinite, &Dglobal_isFinite, 1 },
            { TEXT_decodeURI, &Dglobal_decodeURI, 1 },
            { TEXT_decodeURIComponent, &Dglobal_decodeURIComponent, 1 },
            { TEXT_encodeURI, &Dglobal_encodeURI, 1 },
            { TEXT_encodeURIComponent, &Dglobal_encodeURIComponent, 1 },

            // Dscript unique function properties
            { TEXT_print, &Dglobal_print, 1 },
            { TEXT_println, &Dglobal_println, 1 },
            { TEXT_readln, &Dglobal_readln, 0 },
            { TEXT_getenv, &Dglobal_getenv, 1 },

            // Jscript compatible extensions
            { TEXT_ScriptEngine, &Dglobal_ScriptEngine, 0 },
            { TEXT_ScriptEngineBuildVersion, &Dglobal_ScriptEngineBuildVersion, 0 },
            { TEXT_ScriptEngineMajorVersion, &Dglobal_ScriptEngineMajorVersion, 0 },
            { TEXT_ScriptEngineMinorVersion, &Dglobal_ScriptEngineMinorVersion, 0 },

            // Debug function
            { TEXT_isStrictMode, &Dglobal_isStrictMode, 0 },

        ];

        DnativeFunction.init(this, nfd, DontEnum);

        /*
          Set isolated functions
         */
        Get(TEXT_eval).object.isolated=true;

        // Now handled by AssertExp()
        // Put(TEXT_assert, Dglobal_assert(), DontEnum);

        // Constructor properties

        std.stdio.writefln("global = %x",cast(void*)this);
        //global=this;
        Put(TEXT_global, this, DontEnum);
        Put(TEXT_Object, Dobject_constructor, DontEnum);
        Put(TEXT_Function, Dfunction_constructor, DontEnum);
        Put(TEXT_Array, Darray_constructor, DontEnum);
        Put(TEXT_String, Dstring_constructor, DontEnum);
        Put(TEXT_Boolean, Dboolean_constructor, DontEnum);
        Put(TEXT_Number, Dnumber_constructor, DontEnum);
        Put(TEXT_Date, Ddate_constructor, DontEnum);

        Put(TEXT_JSON, DJSON_constructor, DontEnum);

        Put(TEXT_RegExp, Dregexp_constructor, DontEnum);
        Put(TEXT_Error, Derror_constructor, DontEnum);
        Put(TEXT_Console, Dconsole_constructor, DontEnum);

        foreach(d_string key, Dfunction ctor; ctorTable)
        {
            Put(key, ctor, DontEnum);
        }

        // Other properties

        assert(Dmath_object);
        Put(TEXT_Math, Dmath_object, DontEnum);

        // Build an "arguments" property out of argv[],
        // and add it to the global object.
        Darray arguments;

        arguments = new Darray();
        Put(TEXT_arguments, arguments, DontDelete);
        arguments.ulength=cast(uint)(argv.length);
        for(int i = 0; i < argv.length; i++)
        {
            arguments.Put(i, argv[i].idup, DontEnum);
        }
        arguments.Put(TEXT_callee, &Value.vnull, DontEnum, true);

    }
}
