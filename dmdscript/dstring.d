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


module dmdscript.dstring;

import dmdscript.regexp;
import std.utf;
import std.c.stdlib;
import std.c.string;
import std.exception;
import std.algorithm;
import std.range;
import std.stdio;

import dmdscript.script;
import dmdscript.dobject;
import dmdscript.dregexp;
import dmdscript.darray;
import dmdscript.value;
import dmdscript.threadcontext;
import dmdscript.dfunction;
import dmdscript.text;
import dmdscript.property;
import dmdscript.errmsgs;
import dmdscript.dnative;

//alias script.tchar tchar;

/* ===================== Dstring_fromCharCode ==================== */

Value* Dstring_fromCharCode(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.3.2
    d_string s;
    foreach(ref a;arglist) {
        s~=cast(wchar)a.toUint16;
    }
    ret.putVstring(s);
    return null;
}

/* ===================== Dstring_constructor ==================== */

class DstringConstructor : Dfunction
{
    this()
    {
        super(1, Dfunction_prototype);
        name = "String";

        static enum NativeFunctionData nfd[] =
        [
            { TEXT_fromCharCode, &Dstring_fromCharCode, 1 },
        ];

        DnativeFunction.init(this, nfd, 0);
    }

    override Value* Construct(CallContext *cc, Value *ret, Value[] arglist)
    {
        // ECMA 15.5.2
        d_string s;
        Dobject o;

        s = (arglist.length) ? arglist[0].toText : TEXT_;
        o = new Dstring(s);
        ret.putVobject(o);
        return null;
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        // ECMA 15.5.1
        d_string s;

        s = (arglist.length) ? arglist[0].toText : TEXT_;
        ret.putVstring(s);
        return null;
    }
}


/* ===================== Dstring_prototype_toString =============== */

Value* Dstring_prototype_toString(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    //writef("Dstring.prototype.toString()\n");
    // othis must be a String
    if(!othis.isClass(TEXT_String))
    {
        ret.putVundefined();
        return pthis.RuntimeError(cc.errorInfo,
                                  errmsgtbl[ERR_FUNCTION_WANTS_STRING],
                                  TEXT_toString,
                                  othis.classname);
    }
    else
    {
        Value *v;

        v = &(cast(Dstring)othis).value;
        Value.copy(ret, v);
    }
    return null;
}

/* ===================== Dstring_prototype_valueOf =============== */

Value* Dstring_prototype_valueOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // Does same thing as String.prototype.toString()

    //writef("string.prototype.valueOf()\n");
    // othis must be a String
    if(!othis.isClass(TEXT_String))
    {
        ret.putVundefined();
        return pthis.RuntimeError(cc.errorInfo,
                                  errmsgtbl[ERR_FUNCTION_WANTS_STRING],
                                  TEXT_valueOf,
                                  othis.classname);
    }
    else
    {
        Value *v;

        v = &(cast(Dstring)othis).value;
        Value.copy(ret, v);
    }
    return null;
}

/* ===================== Dstring_prototype_charAt =============== */

Value* Dstring_prototype_charAt(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.4.4

    Value *v;
    uint pos;            // ECMA says pos should be a d_number,
                        // but int should behave the same
    v = arglist.length ? &arglist[0] : &Value.vundefined;
    if ( v.isArrayIndex(pos) ) {
        othis.value.charAt(pos, ret);
    } else if ( std.math.isnan(v.toNumber) ) {
        othis.value.charAt(0, ret);
    } else {
        ret.putVstring(TEXT_);
    }
    return null;
}

/* ===================== Dstring_prototype_charCodeAt ============= */

Value* Dstring_prototype_charCodeAt(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.4.5

    Value *v;
    uint pos;           // ECMA says pos should be a d_number,
                        // but int should behave the same
    v = arglist.length ? &arglist[0] : &Value.vundefined;
    if ( v.isArrayIndex(pos) ) {
        Value charcode;
        othis.value.charAt(pos, &charcode);
        *ret=cast(uint)charcode.string[0];
    } else {
        ret.putVnumber(d_number.nan);
    }
    return null;
}

/* ===================== Dstring_prototype_concat ============= */

Value* Dstring_prototype_concat(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.6
    d_string s;

    //writefln("Dstring.prototype.concat()");

    s = othis.value.toText();
    foreach(a ; arglist) {
        s ~= a.toText;
    }
    ret.putVstring(s);
    return null;
}

/* ===================== Dstring_prototype_indexOf ============= */

Value* Dstring_prototype_indexOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.4.6
    // String.prototype.indexOf(searchString, position)

    Value* v1;
    Value* v2;
    uint pos;           // ECMA says pos should be a d_number,
                        // but I can't find a reason.
    d_string s;

    d_string searchString;
    int k;

    s = othis.value.toText;

    v1 = arglist.length ? &arglist[0] : &Value.vundefined;
    v2 = (arglist.length >= 2) ? &arglist[1] : &Value.vundefined;

    searchString = v1.toText;
    v2.isArrayIndex(pos);

    k=-1;
    foreach(i; pos..s.length-searchString.length) {
        if ( searchString == s[pos..searchString.length] ) {
            k=cast(int)pos;
        }
    }

    ret.putVnumber(k);
    return null;
}

/* ===================== Dstring_prototype_lastIndexOf ============= */

Value* Dstring_prototype_lastIndexOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.8
    // String.prototype.lastIndexOf(searchString, position)

    Value *v1;
    int pos;            // ECMA says pos should be a d_number,
                        // but I can't find a reason.
    d_string s;
    int sUCSdim;
    d_string searchString;
    int k;

    version(all)
    {
        {
            // This is the 'transferable' version
            Value* v;
            Value* a;
            v = othis.Get(TEXT_toString);
            a = v.Call(cc, othis, ret, null);
            if(a)                       // if exception was thrown
                return a;
            s = ret.toText();
        }
    }
    else
    {
        // the 'builtin' version
        s = othis.value.toString();
    }
    sUCSdim = cast(int)std.utf.toUCSindex(s, s.length);

    v1 = arglist.length ? &arglist[0] : &Value.vundefined;
    searchString = v1.toText;
    if(arglist.length >= 2)
    {
        d_number n;
        Value *v = &arglist[1];

        n = v.toNumber();
        if(std.math.isnan(n) || n > sUCSdim)
            pos = sUCSdim;
        else if(n < 0)
            pos = 0;
        else
            pos = cast(int)n;
    }
    else
        pos = sUCSdim;

    //writef("len = %d, p = '%ls'\n", len, p);
    //writef("pos = %d, sslen = %d, ssptr = '%ls'\n", pos, sslen, ssptr);
    //writefln("s = '%s', pos = %s, searchString = '%s'", s, pos, searchString);

    if(searchString.length == 0)
        k = pos;
    else
    {
	  pos = cast(int)std.utf.toUTFindex(s, pos);
        pos += searchString.length;
        if(pos > s.length)
		  pos = cast(int)s.length;
        k = cast(int)std.string.lastIndexOf(s[0 .. pos], searchString);
        //writefln("s = '%s', pos = %s, searchString = '%s', k = %d", s, pos, searchString, k);
        if(k != -1)
		  k = cast(int)std.utf.toUCSindex(s, k);
    }
    ret.putVnumber(k);
    return null;
}

/* ===================== Dstring_prototype_localeCompare ============= */

Value* Dstring_prototype_localeCompare(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.9
    d_string s1;
    d_string s2;
    d_number n;
    Value *v;

    v = &othis.value;
    s1 = v.toText;
    s2 = arglist.length ? arglist[0].toText : Value.vundefined.toText;
    n = localeCompare(cc, s1, s2);
    ret.putVnumber(n);
    return null;
}

/* ===================== Dstring_prototype_match ============= */

Value* Dstring_prototype_match(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.10
    Dregexp r;
    Dobject o;

    if(arglist.length && !arglist[0].isPrimitive() &&
       (o = arglist[0].toObject()).isDregexp())
    {
        ;
    }
    else
    {
        Value regret;

        regret.putVobject(null);
        Dregexp.getConstructor().Construct(cc, &regret, arglist);
        o = regret.object;
    }

    r = cast(Dregexp)o;
    if(r.global.dbool)
    {
        Darray a = new Darray;
        d_int32 n;
        d_int32 i;
        d_int32 lasti;

        i = 0;
        lasti = 0;
        for(n = 0;; n++)
        {
            r.lastIndex.putVnumber(i);
            Dregexp.exec(r, ret, (&othis.value)[0 .. 1], EXEC_STRING);
            if(!ret.string)             // if match failed
            {
                r.lastIndex.putVnumber(i);
                break;
            }
            lasti = i;
            i = cast(d_int32)r.lastIndex.toInt32();
            if(i == lasti)              // if no source was consumed
                i++;                    // consume a character

            a.Put(n, ret, 0);           // a[n] = ret;
        }
        ret.putVobject(a);
    }
    else
    {
        Dregexp.exec(r, ret, (&othis.value)[0 .. 1], EXEC_ARRAY);
    }
    return null;
}

/* ===================== Dstring_prototype_replace ============= */

Value* Dstring_prototype_replace(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.11
    // String.prototype.replace(searchValue, replaceValue)

    d_string string;
    d_string searchString;
    d_string newstring;
    Value *searchValue;
    Value *replaceValue;
    Dregexp r;
    RegExp re;
    d_string replacement;
    d_string result;
    int m;
    int i;
    int lasti;
    dmdscript.regexp.regmatch_t[1] pmatch;
    Dfunction f;
    Value* v;

    v = &othis.value;
    string = v.toText;
    searchValue = (arglist.length >= 1) ? &arglist[0] : &Value.vundefined;
    replaceValue = (arglist.length >= 2) ? &arglist[1] : &Value.vundefined;
    r = Dregexp.isRegExp(searchValue);
    f = Dfunction.isFunction(replaceValue);
    if(r)
    {
        int offset = 0;

        re = r.re;
        i = 0;
        result = string;

        r.lastIndex.putVnumber(0);
        for(;; )
        {
            Dregexp.exec(r, ret, (&othis.value)[0 .. 1], EXEC_STRING);
            if(!ret.string)             // if match failed
                break;

            m = re.re_nsub;
            if(f)
            {
                scope Value* alist=(new Value[m+3]).ptr;
                alist[0].putVstring(ret.string);
                for(i = 0; i < m; i++)
                {
                    alist[1 + i].putVstring(
                        string[re.pmatch[1 + i].rm_so .. re.pmatch[1 + i].rm_eo]);
                }
                alist[m + 1].putVnumber(re.pmatch[0].rm_so);
                alist[m + 2].putVstring(string);
                f.Call(cc, f, ret, alist[0 .. m + 3]);
                replacement = ret.toText;
            }
            else
            {
                newstring = replaceValue.toText;
                replacement = re.replace(newstring);
            }
            int starti = cast(int)re.pmatch[0].rm_so + offset;
            int endi = cast(int)re.pmatch[0].rm_eo + offset;
            result = string[0 .. starti] ~
                     replacement ~
                     string[endi .. $];

            if(re.attributes & RegExp.REA.global)
            {
                offset += replacement.length - (endi - starti);

                // If no source was consumed, consume a character
                lasti = i;
                i = cast(d_int32)r.lastIndex.toInt32();
                if(i == lasti)
                {
                    i++;
                    r.lastIndex.putVnumber(i);
                }
            }
            else
                break;
        }
    }
    else
    {
        int match;

        searchString = searchValue.toText();
        match = cast(int)std.string.indexOf(string, searchString);
        if(match >= 0)
        {
            pmatch[0].rm_so = match;
            pmatch[0].rm_eo = match + searchString.length;
            if(f)
            {
                Value[3] alist;

                alist[0].putVstring(searchString);
                alist[1].putVnumber(pmatch[0].rm_so);
                alist[2].putVstring(string);
                f.Call(cc, f, ret, alist);
                replacement = ret.toText;
            }
            else
            {
                newstring = replaceValue.toText;
                replacement = RegExp.replace3(newstring, string, pmatch);
            }
            result = string[0 .. match] ~
                     replacement ~
                     string[match + searchString.length .. $];
        }
        else
        {
            result = string;
        }
    }

    ret.putVstring(result);
    return null;
}

/* ===================== Dstring_prototype_search ============= */

Value* Dstring_prototype_search(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.12
    Dregexp r;
    Dobject o;

    //writef("String.prototype.search()\n");
    if(arglist.length && !arglist[0].isPrimitive() &&
       (o = arglist[0].toObject()).isDregexp())
    {
        ;
    }
    else
    {
        Value regret;

        regret.putVobject(null);
        Dregexp.getConstructor().Construct(cc, &regret, arglist);
        o = regret.object;
    }

    r = cast(Dregexp)o;
    Dregexp.exec(r, ret, (&othis.value)[0 .. 1], EXEC_INDEX);
    return null;
}

/* ===================== Dstring_prototype_slice ============= */

Value* Dstring_prototype_slice(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.13
    d_int32 start;
    d_int32 end;
    d_int32 sdim;
    d_string s;

    s = othis.value.toText;
    sdim = cast(d_int32)s.length;
    switch(arglist.length)
    {
    case 0:
        start = 0;
        end = sdim;
        break;

    case 1:
        start = arglist[0].toInt32();
        end = sdim;
        break;

    default:
        start = arglist[0].toInt32();
        end = arglist[1].toInt32();
        break;
    }

    if(start < 0)
    {
        start += sdim;
        if(start < 0)
            start = 0;
    }
    else if(start >= sdim)
        start = sdim;

    if(end < 0)
    {
        end += sdim;
        if(end < 0)
            end = 0;
    }
    else if(end >= sdim)
        end = sdim;

    if(start > end)
        end = start;

    ret.putVstring(s[start..end]);
    return null;
}


/* ===================== Dstring_prototype_split ============= */

Value* Dstring_prototype_split(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.14
    // String.prototype.split(separator, limit)
    d_uint32 lim;
    d_uint32 p;
    d_uint32 q;
    d_uint32 e;
    Value* separator = &Value.vundefined;
    Value* limit = &Value.vundefined;
    Dregexp R;
    RegExp re;
    d_string rs;
    d_string T;
    d_string S;
    Darray A;
    int str;

    //writefln("Dstring_prototype_split()");
    switch(arglist.length)
    {
    default:
        limit = &arglist[1];
    case 1:
        separator = &arglist[0];
    case 0:
        break;
    }

    Value *v;
    v = &othis.value;
    S = v.toText();
    A = new Darray;
    if(limit.isUndefined())
        lim = ~0u;
    else
        lim = limit.toUint32();
    p = 0;
    R = Dregexp.isRegExp(separator);
    if(R)       // regular expression
    {
        re = R.re;
        assert(re);
        rs = null;
        str = 0;
    }
    else        // string
    {
        re = null;
        rs = separator.toText;
        str = 1;
    }
    if(lim == 0)
        goto Lret;

    // ECMA v3 15.5.4.14 is specific: "If separator is undefined, then the
    // result array contains just one string, which is the this value
    // (converted to a string)." However, neither Javascript nor Jscript
    // do that, they regard an undefined as being the string "undefined".
    // We match Javascript/Jscript behavior here, not ECMA.

    // Uncomment for ECMA compatibility
    //if (!separator.isUndefined())
    {
        //writefln("test1 S = '%s', rs = '%s'", S, rs);
        if(S.length)
        {
            L10:
            for(q = p; q != S.length; q++)
            {
                if(str)                 // string
                {
                    if(q + rs.length <= S.length && !memcmp(S.ptr + q, rs.ptr, rs.length * wchar.sizeof))
                    {
					    e = q + cast(d_uint32)rs.length;
                        if(e != p)
                        {
                            T = S[p .. q];
                            A.Put(A.ulength, T, 0);
                            if(A.ulength == lim)
                                goto Lret;
                            p = e;
                            goto L10;
                        }
                    }
                }
                else            // regular expression
                {
                    if(re.test(S, q))
                    {
					    q = cast(d_uint32)re.pmatch[0].rm_so;
                        e = cast(d_uint32)re.pmatch[0].rm_eo;
                        if(e != p)
                        {
                            T = S[p .. q];
                            //writefln("S = '%s', T = '%s', p = %d, q = %d, e = %d\n", S, T, p, q, e);
                            A.Put(A.ulength, T, 0);
                            if(A.ulength == lim)
                                goto Lret;
                            p = e;
                            for(uint i = 0; i < re.re_nsub; i++)
                            {
							    int so = cast(int)re.pmatch[1 + i].rm_so;
                                int eo = cast(int)re.pmatch[1 + i].rm_eo;

                                //writefln("i = %d, nsub = %s, so = %s, eo = %s, S.length = %s", i, re.re_nsub, so, eo, S.length);
                                if(so != -1 && eo != -1)
                                    T = S[so .. eo];
                                else
                                    T = null;
                                A.Put(A.ulength, T, 0);
                                if(A.ulength == lim)
                                    goto Lret;
                            }
                            goto L10;
                        }
                    }
                }
            }
            T = S[p .. S.length];
            A.Put(A.ulength, T, 0);
            goto Lret;
        }
        if(str)                 // string
        {
            if(rs.length <= S.length && S[0 .. rs.length] == rs[])
                goto Lret;
        }
        else            // regular expression
        {
            if(re.test(S, 0))
                goto Lret;
        }
    }

    A.Put(0u, S, 0);
    Lret:
    ret.putVobject(A);
    return null;
}


/* ===================== Dstring_prototype_substr ============= */

Value* dstring_substring(d_string s, int sdim, d_number start, d_number end, Value *ret)
{
    d_string sb;
    d_int32 sb_len;

    if(std.math.isnan(start))
        start = 0;
    else if(start > sdim)
        start = sdim;
    else if(start < 0)
        start = 0;

    if(std.math.isnan(end))
        end = 0;
    else if(end > sdim)
        end = sdim;
    else if(end < 0)
        end = 0;

    if(end < start)             // swap
    {
        d_number t;

        t = start;
        start = end;
        end = t;
    }

    ret.putVstring(s[cast(size_t)start..cast(size_t)end]);
    return null;
}

Value* Dstring_prototype_substr(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // Javascript: TDG pg. 689
    // String.prototype.substr(start, length)
    d_number start;
    d_number length;
    d_string s;

    s = othis.value.toText;
    int sdim = cast(int)s.length;
    start = 0;
    length = 0;
    if(arglist.length >= 1)
    {
        start = arglist[0].toInteger();
        if(start < 0)
            start = sdim + start;
        if(arglist.length >= 2)
        {
            length = arglist[1].toInteger();
            if(std.math.isnan(length) || length < 0)
                length = 0;
        }
        else
            length = sdim - start;
    }

    return dstring_substring(s, sdim, start, start + length, ret);
}

/* ===================== Dstring_prototype_substring ============= */

Value* Dstring_prototype_substring(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.4.9
    // String.prototype.substring(start)
    // String.prototype.substring(start, end)
    d_number start;
    d_number end;
    d_string s;

    //writefln("String.prototype.substring()");
    s = othis.value.toText;
    int sUCSdim = cast(int)s.length;
    start = 0;
    end = sUCSdim;
    if(arglist.length >= 1)
    {
        start = arglist[0].toInteger();
        if(arglist.length >= 2)
            end = arglist[1].toInteger();
        //writef("s = '%ls', start = %d, end = %d\n", s, start, end);
    }

    Value* p = dstring_substring(s, sUCSdim, start, end, ret);
    return p;
}

/* ===================== Dstring_prototype_toLowerCase ============= */

enum CASE
{
    Lower,
    Upper,
    LocaleLower,
    LocaleUpper
};

Value* tocase(Dobject othis, Value *ret, CASE caseflag)
{
    d_string s;

    s = othis.value.toText;
    switch(caseflag)
    {
    case CASE.Lower:
        s = std.string.toLower(s);
        break;
    case CASE.Upper:
        s = std.string.toUpper(s);
        break;
    case CASE.LocaleLower:
        s = std.string.toLower(s);
        break;
    case CASE.LocaleUpper:
        s = std.string.toUpper(s);
        break;
    default:
        assert(0);
    }

    ret.putVstring(s);
    return null;
}

Value* Dstring_prototype_toLowerCase(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.4.11
    // String.prototype.toLowerCase()

    //writef("Dstring_prototype_toLowerCase()\n");
    return tocase(othis, ret, CASE.Lower);
}

/* ===================== Dstring_prototype_toLocaleLowerCase ============= */

Value* Dstring_prototype_toLocaleLowerCase(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.17

    //writef("Dstring_prototype_toLocaleLowerCase()\n");
    return tocase(othis, ret, CASE.LocaleLower);
}

/* ===================== Dstring_prototype_toUpperCase ============= */

Value* Dstring_prototype_toUpperCase(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA 15.5.4.12
    // String.prototype.toUpperCase()

    return tocase(othis, ret, CASE.Upper);
}

/* ===================== Dstring_prototype_toLocaleUpperCase ============= */

Value* Dstring_prototype_toLocaleUpperCase(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.5.4.18

    return tocase(othis, ret, CASE.LocaleUpper);
}

/* ===================== Dstring_prototype_anchor ============= */

Value* dstring_anchor(Dobject othis, Value* ret, d_string tag, d_string name, Value[] arglist)
{
    // For example:
    //	"foo".anchor("bar")
    // produces:
    //	<tag name="bar">foo</tag>

    d_string foo = othis.value.toText;
    Value* va = arglist.length ? &arglist[0] : &Value.vundefined;
    d_string bar = va.toText;

    d_string s;

    s = "<"     ~
        tag     ~
        " "     ~
        name    ~
        "=\""   ~
        bar     ~
        "\">"   ~
        foo     ~
        "</"    ~
        tag     ~
        ">";

    ret.putVstring(s);
    return null;
}


Value* Dstring_prototype_anchor(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // Non-standard extension
    // String.prototype.anchor(anchor)
    // For example:
    //	"foo".anchor("bar")
    // produces:
    //	<A NAME="bar">foo</A>

    return dstring_anchor(othis, ret, "A", "NAME", arglist);
}

Value* Dstring_prototype_fontcolor(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_anchor(othis, ret, "FONT", "COLOR", arglist);
}

Value* Dstring_prototype_fontsize(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_anchor(othis, ret, "FONT", "SIZE", arglist);
}

Value* Dstring_prototype_link(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_anchor(othis, ret, "A", "HREF", arglist);
}


/* ===================== Dstring_prototype bracketing ============= */

/***************************
 * Produce <tag>othis</tag>
 */

Value* dstring_bracket(Dobject othis, Value* ret, d_string tag)
{
    d_string foo = othis.value.toText;
    d_string s;

    s = "<"     ~
        tag     ~
        ">"     ~
        foo     ~
        "</"    ~
        tag     ~
        ">";

    ret.putVstring(s);
    return null;
}

Value* Dstring_prototype_big(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // Non-standard extension
    // String.prototype.big()
    // For example:
    //	"foo".big()
    // produces:
    //	<BIG>foo</BIG>

    return dstring_bracket(othis, ret, "BIG");
}

Value* Dstring_prototype_blink(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "BLINK");
}

Value* Dstring_prototype_bold(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "B");
}

Value* Dstring_prototype_fixed(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "TT");
}

Value* Dstring_prototype_italics(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "I");
}

Value* Dstring_prototype_small(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "SMALL");
}

Value* Dstring_prototype_strike(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "STRIKE");
}

Value* Dstring_prototype_sub(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "SUB");
}

Value* Dstring_prototype_sup(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    return dstring_bracket(othis, ret, "SUP");
}



/* ===================== Dstring_prototype ==================== */

class DstringPrototype : Dstring
{
    this()
    {
        super(Dobject_prototype);

        Put(TEXT_constructor, Dstring_constructor, DontEnum);

        static enum NativeFunctionData nfd[] =
        [
            { TEXT_toString, &Dstring_prototype_toString, 0 },
            { TEXT_valueOf, &Dstring_prototype_valueOf, 0 },
            { TEXT_charAt, &Dstring_prototype_charAt, 1 },
            { TEXT_charCodeAt, &Dstring_prototype_charCodeAt, 1 },
            { TEXT_concat, &Dstring_prototype_concat, 1 },
            { TEXT_indexOf, &Dstring_prototype_indexOf, 1 },
            { TEXT_lastIndexOf, &Dstring_prototype_lastIndexOf, 1 },
            { TEXT_localeCompare, &Dstring_prototype_localeCompare, 1 },
            { TEXT_match, &Dstring_prototype_match, 1 },
            { TEXT_replace, &Dstring_prototype_replace, 2 },
            { TEXT_search, &Dstring_prototype_search, 1 },
            { TEXT_slice, &Dstring_prototype_slice, 2 },
            { TEXT_split, &Dstring_prototype_split, 2 },
            { TEXT_substr, &Dstring_prototype_substr, 2 },
            { TEXT_substring, &Dstring_prototype_substring, 2 },
            { TEXT_toLowerCase, &Dstring_prototype_toLowerCase, 0 },
            { TEXT_toLocaleLowerCase, &Dstring_prototype_toLocaleLowerCase, 0 },
            { TEXT_toUpperCase, &Dstring_prototype_toUpperCase, 0 },
            { TEXT_toLocaleUpperCase, &Dstring_prototype_toLocaleUpperCase, 0 },
            { TEXT_anchor, &Dstring_prototype_anchor, 1 },
            { TEXT_fontcolor, &Dstring_prototype_fontcolor, 1 },
            { TEXT_fontsize, &Dstring_prototype_fontsize, 1 },
            { TEXT_link, &Dstring_prototype_link, 1 },
            { TEXT_big, &Dstring_prototype_big, 0 },
            { TEXT_blink, &Dstring_prototype_blink, 0 },
            { TEXT_bold, &Dstring_prototype_bold, 0 },
            { TEXT_fixed, &Dstring_prototype_fixed, 0 },
            { TEXT_italics, &Dstring_prototype_italics, 0 },
            { TEXT_small, &Dstring_prototype_small, 0 },
            { TEXT_strike, &Dstring_prototype_strike, 0 },
            { TEXT_sub, &Dstring_prototype_sub, 0 },
            { TEXT_sup, &Dstring_prototype_sup, 0 },
        ];

        DnativeFunction.init(this, nfd, DontEnum);
    }
}

/* ===================== Dstring ==================== */

class Dstring : Dobject
{
    this(d_string s)
    {
        super(getPrototype());
        classname = TEXT_String;

        Put(TEXT_length, cast(uint)s.length, DontEnum | DontDelete, true );
        value.putVstring(s);
    }

    this(Dobject prototype)
    {
        super(prototype);

        classname = TEXT_String;
        Put(TEXT_length, 0, DontEnum | DontDelete | ReadOnly);
        value.putVstring(null);
    }

    override d_string getTypeof() const {
        if (CallContext.currentcc.isStrictMode) {
            return TEXT_string;
        } else {
            return super.getTypeof;
        }
    }

    static void init()
    {
        Dstring_constructor = new DstringConstructor();
        Dstring_prototype = new DstringPrototype();

        Dstring_constructor.Put(TEXT_prototype, Dstring_prototype, DontEnum | DontDelete | ReadOnly);
    }

    static Dfunction getConstructor()
    {
        return Dstring_constructor;
    }

    static Dobject getPrototype()
    {
        return Dstring_prototype;
    }
}
