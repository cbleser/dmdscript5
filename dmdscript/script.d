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

module dmdscript.script;

import std.string;
import std.c.stdlib;
import std.c.stdarg;
import std.conv;
import std.stdio;
alias size_t unsigned;
alias sizediff_t signed;

import dmdscript.irstate;
import dmdscript.opcodes;

/* =================== Configuration ======================= */

const uint MAJOR_VERSION = 5;       // ScriptEngineMajorVersion
const uint MINOR_VERSION = 5;       // ScriptEngineMinorVersion

const uint BUILD_VERSION = 1;       // ScriptEngineBuildVersion

const uint JSCRIPT_CATCH_BUG = 1;   // emulate Jscript's bug in scoping of
                                    // catch objects in violation of ECMA
const uint JSCRIPT_ESCAPEV_BUG = 0; // emulate Jscript's bug where \v is
                                    // not recognized as vertical tab

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

alias wchar d_char;

alias ulong number_t;
alias double real_t;

alias uint Loc;                 // file location (line number)

enum error_type_t {
    syntaxerror,
    evalerror,
    referenceerror,
    rangeerror,
    typeerror,
    urierror
}

struct ErrInfo
{
    d_string message;           // error message (null if no error)
    d_string srcline;           // string of source line (null if not known)
    d_string sourceid;          // Usually points to the name of the source file
    Loc       linnum;            // source line number (1 based, 0 if not available)
    int      charpos;           // character position (1 based, 0 if not available)
    CallContext* cc;            // Points to the context where the error occures

    error_type_t etype;         // Runtime error type;
    @property Loc linenum() {
        if (cc && cc.code) {
            return cc.code.linenum;
        }
        return linnum;
    }
}

class ScriptException : Exception
{
    ErrInfo ei;

    this(d_string msg, string file = __FILE__, size_t line = __LINE__){
        ei.message = msg;
        super(fromDstring(msg), file, line);
    }


    this(ErrInfo pei, string file = __FILE__, size_t line = __LINE__) {
        ei = pei;
        d_string msg=ei.message;
        if (ei.linenum) {
            msg~=format("\n%s:%s:%s %s", ei.sourceid, ei.linenum, ei.charpos, ei.srcline);
        }
        super(fromDstring(msg), file, line);
    }
}

int logflag;    // used for debugging


// Aliases for script primitive types
alias bool d_boolean;
alias double d_number;
alias int d_int32;
alias uint d_uint32;
alias ushort d_uint16;
alias immutable(wchar)[] d_string;

import dmdscript.value;
import dmdscript.dobject;
import dmdscript.program;
import dmdscript.text;
import dmdscript.functiondefinition;

struct CallContext
{
    static CallContext* currentcc; // Set the current call context
                                   // (used for getters and setters)
    Dobject[]          scopex; // current scope chain
    Dobject            variable;         // object for variable instantiation
    Dobject            global;           // global object
    // We use scopex.length instead
    // uint               scoperoot;        // number of entries in scope[] starting from 0
    //                                      // to copy onto new scopes
    uint               globalroot;       // number of entries in scope[] starting from 0
                                         // that are in the "global" context. Always <= scoperoot
    void*              lastnamedfunc;    // points to the last named function added as an event
    Program            prog;
    Dobject            callerothis;      // caller's othis
    Dobject            caller;           // caller function object
    FunctionDefinition callerf;

    Value value;                   // place to store exception; must be same size as Value
    IR*                code;             // error IR code (0 if not known)

    int                Interrupt;  // !=0 if cancelled due to interrupt
    bool               strict_mode;  // Ecmascript 5 'use strict' function depth
//    bool               isolated;  // This flag is used as an isolated
                                   // script (this === undefined)
//    bool               iseval;
    bool isStrictMode() const {
        return strict_mode;
    }


    // static Dobject[] clone(Dobject[] scopex) {
    //     Dobject[] result=new Dobject[scopex.length];
    //     foreach(i,o;scopex) {
    //         result[i]=o.clone;
    //     }
    //     return result;
    // }

    CallContext* clone() {
        CallContext* cc=new CallContext;
        cc.scopex=new Dobject[scopex.length];
        foreach(i,o;scopex) {
            cc.scopex[i]=o.clone;
        }
        cc.prog=prog;
        cc.global=global;
        cc.globalroot=globalroot;
        cc.variable=variable.clone;
        cc.callerothis=callerothis;
        return cc;
    }
// Get the text of the source line at Loc
    d_string locToSrcLine(Loc loc) const {
        return dmdscript.lexer.Lexer.locToSrcLine(prog.srctext.ptr, loc);
    }
}

ErrInfo errorInfo(CallContext* cc, IR* code=null) {
    ErrInfo result;
    result.cc=(cc)?cc:CallContext.currentcc;
    if (cc) {
        if (code) {
            result.cc.code=code;
        }
        result.srcline=cc.locToSrcLine(result.linenum);
    }
    return result;
}

struct Global
{
    string copyright = "Copyright (c) 1999-2010 by Digital Mars";
    string written = "by Walter Bright";
}

Global global;

string banner()
{
    return std.string.format(
               "DMDSsript-2 v0.1rc1\n",
               "Compiled by Digital Mars DMD D compiler\n"
               "http://www.digitalmars.com\n",
               "Fork of the original DMDScript 1.16\n",
               global.written,"\n",
               global.copyright
               );
}

bool isStrWhiteSpaceChar(dchar c)
{
    switch(c)
    {
    case ' ':
    case '\t':
    case 0xA0:          // <NBSP>
    case '\f':
    case '\v':
    case '\r':
    case '\n':
    case 0x2028:        // <LS>
    case 0x2029:        // <PS>
// Unicode Space Seperators
    case 0x1680:        // <OGHAM SPACE MARK>
    case 0x180E:        // <MONGALIAN VOWEL SEPARATOR>
    case 0x2000:        // <EN QUAD>
    case 0x2001:        // <EM QUAD>
    case 0x2002:        // <EN SPACE>
    case 0x2003:        // <EM SPACE>
    case 0x2004:        // <THREE-PER-EM SPACE>
    case 0x2005:        // <FOUR-PER-EM SPACE>
    case 0x2006:        // <SIX-PER-EM SPACE>
    case 0x2007:        // <FIGURE SPACE>
    case 0x2008:        // <PUNCTUATION SPACE>
    case 0x2009:        // <THIN SPACE>
    case 0x200A:        // <HAIR SPACE>
    case 0x202F:        // <NARROW NO-BREAK SPACE>
    case 0x205F:        // <MEDIUM MATHEMATICAL SPACE>
    case 0x3000:        // <IDEOGRAPHIC SPACE>
        return true;

    default:
        break;
    }
    return false;
}


/************************
 * Convert d_string to an index, if it is one.
 * Returns:
 *	true	it's an index, and *index is set
 *	false	it's not an index
 */

bool StringToIndex(d_string name, out d_uint32 index)
{
    if(name.length)
    {
        d_uint32 i = 0;
        foreach(j,c; name) {
            switch(c)
            {
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                if((i == 0 && j) ||             // if leading zeros
                   i >= uint.max / 10)        // or overflow
                    goto Lnotindex;
                i = i * 10 + c - '0';
                break;

            default:
                goto Lnotindex;
            }
        }
        index = i;
        return true;
    }

    Lnotindex:
    return false;
}


/********************************
 * Parse string numeric literal into a number.
 * Input:
 *	parsefloat	0: convert per ECMA 9.3.1
 *			1: convert per ECMA 15.1.2.3 (global.parseFloat())
 */

d_number StringNumericLiteral(d_string string, out size_t endidx, int parsefloat)
{
    // Convert StringNumericLiteral using ECMA 9.3.1
    d_number number;
    int sign = 0;
    size_t i;
    size_t len;
    size_t eoff;
	if(!string.length)
		return d_number.nan;
    // Skip leading whitespace
    eoff = string.length;
    foreach(size_t j, dchar c; string)
    {
        if(!isStrWhiteSpaceChar(c))
        {
            eoff = j;
            break;
        }
    }
    string = string[eoff .. $];
    len = string.length;

    // Check for [+|-]
    i = 0;
    if(len)
    {
        switch(string[0])
        {
        case '+':
            sign = 0;
            i++;
            break;

        case '-':
            sign = 1;
            i++;
            break;

        default:
            sign = 0;
            break;
        }
    }

    size_t inflen = TEXT_Infinity.length;
    if(len - i >= inflen &&
       string[i .. i + inflen] == TEXT_Infinity)
    {
        number = sign ? -d_number.infinity : d_number.infinity;
        endidx = eoff + i + inflen;
    }
    else if(len - i >= 2 &&
            string[i] == '0' && (string[i + 1] == 'x' || string[i + 1] == 'X'))
    {
        // Check for 0[x|X]HexDigit...
        number = 0;
        if(parsefloat)
        {   // Do not recognize the 0x, treat it as if it's just a '0'
            i += 1;
        }
        else
        {
            i += 2;
            for(; i < len; i++)
            {
                wchar c;

                c = string[i];          // don't need to decode UTF here
                if('0' <= c && c <= '9')
                    number = number * 16 + (c - '0');
                else if('a' <= c && c <= 'f')
                    number = number * 16 + (c - 'a' + 10);
                else if('A' <= c && c <= 'F')
                    number = number * 16 + (c - 'A' + 10);
                else
                    break;
            }
        }
        if(sign)
            number = -number;
        endidx = eoff + i;
    }
    else if ( string[i .. len] != "infinity" )
    {
        char* endptr;
        immutable(char)[] str=fromDstring(string[i..len]);
        const(char)* s = std.string.toStringz(str);

        //endptr = s;//Fixed: No need to fill endptr prior to stdtod
        number = std.c.stdlib.strtod(s, &endptr);
        endidx = (endptr - s) + i;

        //printf("s = '%s', endidx = %d, eoff = %d, number = %g\n", s, endidx, eoff, number);

        // Correctly produce a -0 for the
        // string "-1e-2000"
        if(sign)
            number = -number;
        if(endidx == i && (parsefloat || i != 0))
            number = d_number.nan;
        endidx += eoff;
    }

    return number;
}




int localeCompare(CallContext *cc, d_string s1, d_string s2)
{   // no locale support here
    return std.string.cmp(s1, s2);
}

interface ScriptType {
    d_string toText();
}

d_string format(...) {
    d_string result;
    std.format.doFormat((dchar c) {result~=cast(wchar)c;}, _arguments, _argptr);
    return result;
}

d_string sformat(d_string buf, TypeInfo[] arguments, va_list argptr){
    std.format.doFormat((dchar c) {buf~=cast(wchar)c;}, arguments, argptr);
    return buf;
}

d_string toDstring(const(char)[] s) {
    d_string result;
    foreach(dchar c; s) {
        wchar[2] buf;
        result~=std.utf.toUTF16(buf, c);
    }
    return result;
}

immutable(char)[] fromDstring(d_string s) {
    immutable(char)[] result;
    foreach(dchar c; s) {
        char[4] buf;
        result~=std.utf.toUTF8(buf, c);
    }
    return result;
}
