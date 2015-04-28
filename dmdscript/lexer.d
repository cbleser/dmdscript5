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

/* Lexical Analyzer
 */

module dmdscript.lexer;

import std.range;
import std.algorithm;
import std.stdio;
//import std.string;
//import std.utf;
import std.outbuffer;
import std.c.stdlib;
import core.vararg;

import dmdscript.script;
import dmdscript.text;
import dmdscript.identifier;
import dmdscript.scopex;
import dmdscript.errmsgs;
import dmdscript.value;

alias std.ascii.isAlphaNum isalnum;
alias std.ascii.isDigit    isdigit;
alias std.ascii.isPrintable isprint;

/* Tokens:
   (	)
   [	]
   {	}
   <	>	<=	>=	==	!=
   ===     !==
   <<	>>	<<=	>>=	>>>	>>>=
   +	-	+=	-=
   *	/	%	*=	/=	%=
   &	|   ^	&=	|=	^=
   =	!	~
   ++	--
   .	:	,
   ?	&&	||
*/
static assert(wchar.sizeof is ushort.sizeof);

enum TOK {
    TOKreserved,

    // Other
    TOKlparen, TOKrparen,
    TOKlbracket, TOKrbracket,
    TOKlbrace, TOKrbrace,
    TOKcolon, TOKneg,
    TOKpos,
    TOKsemicolon, TOKeof,
    TOKarray, TOKcall,
    TOKarraylit, TOKobjectlit,
    TOKcomma, TOKassert,

    // Operators
    TOKless, TOKgreater,
    TOKlessequal, TOKgreaterequal,
    TOKequal, TOKnotequal,
    TOKidentity, TOKnonidentity,
    TOKshiftleft, TOKshiftright,
    TOKshiftleftass, TOKshiftrightass,
    TOKushiftright, TOKushiftrightass,
    TOKplus, TOKminus, TOKplusass, TOKminusass,
    TOKmultiply, TOKdivide, TOKpercent,
    TOKmultiplyass, TOKdivideass, TOKpercentass,
    TOKand, TOKor, TOKxor,
    TOKandass, TOKorass, TOKxorass,
    TOKassign, TOKnot, TOKtilde,
    TOKplusplus, TOKminusminus, TOKdot,
    TOKquestion, TOKandand, TOKoror,

    // Leaf operators
    TOKnumber, TOKidentifier, TOKstring,
    TOKregexp, TOKreal,

    // Keywords
    TOKbreak, TOKcase, TOKcontinue,
    TOKdefault, TOKdelete, TOKdo,
    TOKelse, TOKexport, TOKfalse,
    TOKfor, TOKfunction, TOKif,
    TOKimport, TOKin, TOKnew,
    TOKnull, TOKreturn,
    TOKswitch, TOKthis, TOKtrue,
    TOKtypeof, TOKvar, TOKvoid,
    TOKwhile, TOKwith,

    // Reserved for ECMA extensions
    TOKcatch, TOKclass,
    TOKconst, TOKdebugger,
    TOKenum, TOKextends,
    TOKfinally, TOKsuper,
    TOKthrow, TOKtry,

    // Java keywords reserved for unknown reasons
    // obsoleted keyword from Ecmascipt 3
    TOKabstract, TOKboolean,
    TOKbyte, TOKchar,
    TOKdouble, TOKfinal,
    TOKfloat, TOKgoto,
    TOKinstanceof,
    TOKint, TOKinterface,
    TOKlong, TOKnative,
    TOKpackage,
    TOKprotected, TOKpublic,
    TOKshort, TOKstatic,
    TOKsynchronized, TOKthrows,
    TOKtransient,

    // Future reserved words
    TOKimplements,
    TOKlet,
    TOKprivate,
    TOKyield,
    TOKinterace,
    // Illegal
    TOKillegalUnicode,
//    TOKmax
};

int isoctal(dchar c)
{
    return('0' <= c && c <= '7');
}

int isasciidigit(dchar c)
{
    return('0' <= c && c <= '9');
}

int isasciilower(dchar c)
{
    return('a' <= c && c <= 'z');
}

int isasciiupper(dchar c)
{
    return('A' <= c && c <= 'Z');
}
int ishex(dchar c)
{
    return
        ('0' <= c && c <= '9') ||
        ('a' <= c && c <= 'f') ||
        ('A' <= c && c <= 'F');
}


/******************************************************/

struct Token
{
    Token *next;
    immutable(wchar) *ptr;       // pointer to first character of this token within buffer
    uint   linnum;
    TOK    value;
    immutable(wchar) *sawLineTerminator; // where we saw the last line terminator
    union
        {
            number_t    intvalue;
            real_t      realvalue;
            d_string    string;

            Identifier *ident;
        };

    static d_string tochars[TOK.max];

    static Category category[TOK.max];

    static Token* alloc(Lexer* lex)
        {
            Token *t;

            if(lex.freelist)
            {
                t = lex.freelist;
                lex.freelist = t.next;
                return t;
            }

            return new Token();
        }

    void print() {
        writefln(toText);
    }

    d_string toText()
        {
            d_string p;

            with(TOK) switch(value)
            {
            case TOKnumber:
                version(dmd_pre_2060) {
                    p = std.string.format(intvalue);
                } else {
                    p = Value.numberToString(intvalue);
                }
                break;

            case TOKreal:

                p = Value.numberToString(realvalue);
/*
                long l = cast(long)realvalue;
                if(l == realvalue)
                    version(dmd_pre_2060) {
                        p = std.string.format(l);
                    } else {
                    p = std.string.format("%d",l);
                }
                else
                    version(dmd_pre_2060) {
                        p = std.string.format(realvalue);
                    } else {
                    p = std.string.format("%f",realvalue);
                }
*/
                break;

            case TOKstring:
            case TOKregexp:
                p = string;
                break;

            case TOKidentifier:
                p = ident.toText;
                break;

            default:
                p = toText(value);
                break;
            }
            return p;
        }

    static d_string toText(TOK value)
        {
            d_string p;

            p = tochars[value];
            if(!p)
                p = dmdscript.script.format("TOK%d", value);
            return p;
        }

    // static TOK ES3Reserved(TOK value) {
    //     with (Category)
    //         return ( category[value] & ( Symbol | Used | Obsolete | Reserved ) ) ? value : TOKreserved;
    // }

    static TOK ES5Reserved(TOK value) {
	with (Category)
            return ( category[value] & ( Symbol | Used | Reserved | NewReserved ) )? value: TOK.TOKreserved;
    }

    static TOK ES5StrictModeReserved(TOK value) {
	with (Category)
            return ( category[value] & ( Symbol | Used | Reserved | NewReserved | FutureReserved ) ) ? value : TOK.TOKreserved;
    }

    static this()
        {
            uint u;
            TOK v;
            Category c;
            for(u = 0; u < keywords.length; u++)
            {
                d_string s;

                //writefln("keyword[%d] = '%s'", u, keywords[u].name);
                s = keywords[u].name;
                v = keywords[u].value;
                c = keywords[u].category;

                //writefln("tochars[%d] = '%s'", v, s);
                Token.tochars[v] = s;
                Token.category[v] = c;
                akeyword[s]=keywords[u];
            }
            with(TOK) {
                Token.tochars[TOKreserved] = "reserved";
                Token.tochars[TOKeof] = "EOF";
                Token.tochars[TOKlbrace] = "{";
                Token.tochars[TOKrbrace] = "}";
                Token.tochars[TOKlparen] = "(";
                Token.tochars[TOKrparen] = ")";
                Token.tochars[TOKlbracket] = "[";
                Token.tochars[TOKrbracket] = "]";
                Token.tochars[TOKcolon] = ":";
                Token.tochars[TOKsemicolon] = ";";
                Token.tochars[TOKcomma] = ",";
                Token.tochars[TOKor] = "|";
                Token.tochars[TOKorass] = "|=";
                Token.tochars[TOKxor] = "^";
                Token.tochars[TOKxorass] = "^=";
                Token.tochars[TOKassign] = "=";
                Token.tochars[TOKless] = "<";
                Token.tochars[TOKgreater] = ">";
                Token.tochars[TOKlessequal] = "<=";
                Token.tochars[TOKgreaterequal] = ">=";
                Token.tochars[TOKequal] = "==";
                Token.tochars[TOKnotequal] = "!=";
                Token.tochars[TOKidentity] = "===";
                Token.tochars[TOKnonidentity] = "!==";
                Token.tochars[TOKshiftleft] = "<<";
                Token.tochars[TOKshiftright] = ">>";
                Token.tochars[TOKushiftright] = ">>>";
                Token.tochars[TOKplus] = "+";
                Token.tochars[TOKplusass] = "+=";
                Token.tochars[TOKminus] = "-";
                Token.tochars[TOKminusass] = "-=";
                Token.tochars[TOKmultiply] = "*";
                Token.tochars[TOKmultiplyass] = "*=";
                Token.tochars[TOKdivide] = "/";
                Token.tochars[TOKdivideass] = "/=";
                Token.tochars[TOKpercent] = "%";
                Token.tochars[TOKpercentass] = "%=";
                Token.tochars[TOKand] = "&";
                Token.tochars[TOKandass] = "&=";
                Token.tochars[TOKdot] = ".";
                Token.tochars[TOKquestion] = "?";
                Token.tochars[TOKtilde] = "~";
                Token.tochars[TOKnot] = "!";
                Token.tochars[TOKandand] = "&&";
                Token.tochars[TOKoror] = "||";
                Token.tochars[TOKplusplus] = "++";
                Token.tochars[TOKminusminus] = "--";
                Token.tochars[TOKcall] = "CALL";
            }
        }



}




/*******************************************************************/

class Lexer
{
    Identifier[d_string] stringtable;
    Token* freelist;
    bool iseval;

    d_string sourcename;        // for error message strings

    d_string base;             // pointer to start of buffer
    immutable(wchar)* end;      // past end of buffer
    immutable(wchar)* p;        // current character
    uint currentline;
    Token token;
    OutBuffer stringbuffer;
    int useStringtable;         // use for Identifiers

    ErrInfo errinfo;            // syntax error information
    //    static bool inited;

    version(Ecmascript5) {
        bool keyword_as_property;
        bool first_command_in_block; // Enables the check for 'use strict';
        bool use_strict;
        bool inside_function_block;
    }


    this(d_string sourcename, immutable(char)[] base, int useStringTable) {
        init(sourcename, std.utf.toUTF16(base), useStringTable);
    }

    this(d_string sourcename, d_string base, int useStringtable) {
        init(sourcename, base, useStringtable);
    }

    private void init(d_string sourcename, d_string base, int useStringtable)
        {
            //writefln("Lexer::Lexer(base = '%s')\n",base);
            // if(!inited)
            //     init();

            std.c.string.memset(&token, 0, token.sizeof);
            this.useStringtable = useStringtable;
            this.sourcename = sourcename;
            if(!base.length || (base[$ - 1] != 0 && base[$ - 1] != 0x1A))
                base ~= cast(wchar)0x1A;
            this.base = base;
            this.end = base.ptr + base.length;
            p = base.ptr;
            currentline = 1;
            freelist = null;
        }


    ~this()
        {
            //writef(L"~Lexer()\n");
            freelist = null;
            sourcename = null;
            base = null;
            end = null;
            p = null;
        }

/++
    dchar get(immutable(tchar)* p)
        {
            size_t idx = p - base.ptr;
            return std.utf.decode(base, idx);
        }

    immutable(tchar) * inc(immutable(tchar) * p)
        {
            size_t idx = p - base.ptr;
            std.utf.decode(base, idx);
            return base.ptr + idx;
        }
++/

    void error(int msgnum)
        {
            error(errmsgtbl[msgnum]);
        }

    void error(...)
        {
            uint linnum = 1;
            immutable(wchar)* s;
            immutable(wchar)* slinestart;
            immutable(wchar)* slineend;
            d_string buf;

            //FuncLog funclog(L"Lexer.error()");
            //writefln("TEXT START ------------\n%ls\nTEXT END ------------------", base);

            // Find the beginning of the line
            slinestart = base.ptr;
            for(s = base.ptr; s != p; s++)
            {
                if(*s == '\n')
                {
                    linnum++;
                    slinestart = s + 1;
                }
            }

            // Find the end of the line
            for(;; )
            {
                switch(*s)
                {
                case '\n':
                case 0:
                case 0x1A:
                    break;
                default:
                    s++;
                    continue;
                }
                break;
            }
            slineend = s;

            buf = dmdscript.script.format("%s(%d) : Error: ", sourcename, linnum);


            std.format.doFormat((dchar c) {buf~=cast(wchar)c;}, _arguments, _argptr);

            if(!errinfo.message)
            {
                uint len;

                errinfo.message = buf; // temporary
                errinfo.linnum = linnum;
                errinfo.charpos = cast(uint)(p - slinestart);

                len = cast(uint)(slineend - slinestart);
                errinfo.srcline = slinestart[0 .. len];
            }

            // Consume input until the end
            while(*p != 0x1A && *p != 0)
                p++;
            token.next = null;              // dump any lookahead

            version(none)
            {
                writefln(errinfo.message);
                fflush(stdout);
                exit(EXIT_FAILURE);
            }
        }

    /************************************************
     * Given source text, convert loc to a string for the corresponding line.
     */

    static d_string locToSrcLine(immutable(wchar)* src, Loc loc)
        {
            immutable(wchar)* slinestart;
            immutable(wchar)* slineend;
            immutable(wchar)* s;
            uint linnum = 1;
            uint len;

            if(!src)
                return null;
            slinestart = src;
            for(s = src;; s++)
            {
                switch(*s)
                {
                case '\n':
                    if(linnum == loc)
                    {
                        slineend = s;
                        break;
                    }
                    slinestart = s + 1;
                    linnum++;
                    continue;

                case 0:
                case 0x1A:
                    slineend = s;
                    break;

                default:
                    continue;
                }
                break;
            }

            // Remove trailing \r's
            while(slinestart < slineend && slineend[-1] == '\r')
                --slineend;

            len = cast(uint)(slineend - slinestart);
            return slinestart[0 .. len];
        }


    TOK nextToken()
        {
            Token *t;

            if(token.next)
            {
                t = token.next;
                token = *t;
                t.next = freelist;
                freelist = t;
            }
            else
            {
                scan(&token);
            }
            //token.print();
            return token.value;
        }

    Token* peek(Token* ct)
        {
            Token* t;

            if(ct.next)
                t = ct.next;
            else
            {
                t = Token.alloc(&this);
                scan(t);
                t.next = null;
                ct.next = t;
            }
            return t;
        }

    void insertSemicolon(immutable(wchar) *loc)
        {
            // Push current token back into the input, and
            // create a new current token that is a semicolon
            Token *t;

            t = Token.alloc(&this);
            *t = token;
            token.next = t;
            token.value = TOK.TOKsemicolon;
            token.ptr = loc;
            token.sawLineTerminator = null;
        }

    /**********************************
     * Horrible kludge to support disambiguating TOKregexp from TOKdivide.
     * The idea is, if we are looking for a TOKdivide, and find instead
     * a TOKregexp, we back up and rescan.
     */

    void rescan()
        {
            token.next = null;      // no lookahead
            // should put on freelist
            p = token.ptr + 1;
        }


    /****************************
     * Turn next token in buffer into a token.
     */

    void scan(Token *t) {
        wchar c;
        wchar d;


        //writefln("Lexer.scan()");
        t.sawLineTerminator = null;
        with(TOK) {
            for(;; ) {
                d_string id;
                t.ptr = p;
                //t.linnum = currentline;
                // writefln("p = %04x:%c",*p,*p);
                //writefln("p = %x, *p = x%02x, '%s'",cast(uint)p,*p,*p);
                switch(*p)
                {
                case 0:
                case 0x1A:
                    t.value = TOKeof;               // end of file
                    return;

                case ' ':
                case '\t':
                case '\v':
                case '\f':
                case 0xA0:                          // no-break space
                    p++;
                    continue;                       // skip white space

                case '\n':                          // line terminator
                    currentline++;
                case '\r':
                case '\u2028':
                case '\u2029':
                    t.sawLineTerminator = p;
                    p++;
                    continue;

                case '"':
                case '\'':
                    t.string = string(*p);
                    t.value = TOKstring;
                    return;

                case '0':       case '1':   case '2':   case '3':   case '4':
                case '5':       case '6':   case '7':   case '8':   case '9':
                    t.value = number(t);
                    return;

                case 'a':       case 'b':   case 'c':   case 'd':   case 'e':
                case 'f':       case 'g':   case 'h':   case 'i':   case 'j':
                case 'k':       case 'l':   case 'm':   case 'n':   case 'o':
                case 'p':       case 'q':   case 'r':   case 's':   case 't':
                case 'u':       case 'v':   case 'w':   case 'x':   case 'y':
                case 'z':
                case 'A':       case 'B':   case 'C':   case 'D':   case 'E':
                case 'F':       case 'G':   case 'H':   case 'I':   case 'J':
                case 'K':       case 'L':   case 'M':   case 'N':   case 'O':
                case 'P':       case 'Q':   case 'R':   case 'S':   case 'T':
                case 'U':       case 'V':   case 'W':   case 'X':   case 'Y':
                case 'Z':
                case '_':
                case '$':
                Lidentifier:
                    {
                        static bool isidletter(wchar d)
                        {
                            return isalnum(d) || d == '_' || d == '$' || (d >= 0x80 && std.uni.isAlpha(d));
                        }

                        do
                        {
                            p+=1; // = inc(p);
                            d=*p; // = get(p);
                            if(d == '\\' && p[1] == 'u')
                            {
                              Lidentifier2:
                                // std.stdio.writeln("unicode");
                                id = t.ptr[0 .. p - t.ptr].idup;
                                auto ps = p;
                                p++;
                                d = unicode();
                                switch (d) {
                                case '\u2029':
                                    t.value = TOKillegalUnicode;
                                    t.string =t.ptr[0..p-t.ptr].idup;
                                    break;
                                default:
                                }
                                if(!isidletter(d))
                                {
                                    p = ps;
                                    break;
                                }
                                id~=d;
                                //dmdscript.utf.encode(id, d);
                                for(;; )
                                {
                                    d = *p;
                                    if(d == '\\' && p[1] == 'u')
                                    {
                                        //  std.stdio.writeln("Unicode");
                                        auto pstart = p;
                                        p++;
                                        d = unicode();
                                        if(isidletter(d)) {

                                            //dmdscript.utf.encode(id, d);
                                            id~=d;
                                        } else {
                                            p = pstart;
                                            goto Lidentifier3;
                                        }
                                    }
                                    else if(isidletter(d))
                                    {
                                        //dmdscript.utf.encode(id, d);
                                        id~=d;
                                        p+=1;// = inc(p);
                                    }
                                    else
                                        goto Lidentifier3;
                                }
                            }
                        } while(isidletter(d));
                        id = t.ptr[0 .. p - t.ptr];
                      Lidentifier3:
                        //printf("id = '%.*s'\n", id);
                        if (id.length) {
                            t.value = isKeyword(id);
                            if(t.value)
                                return;
                            if(useStringtable)
                            {     //Identifier* i = &stringtable[id];
                                Identifier* i = id in stringtable;
                                if(!i)
                                {
                                    stringtable[id] = Identifier.init;
                                    i = id in stringtable;
                                }
                                i.put(id);
                                // i.value.toHash();
                                t.ident = i;
                            }
                            else
                                t.ident = Identifier(id);
                            t.value = TOKidentifier;
                        }
                        return;
                    }

                case '/':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKdivideass;
                        return;
                    }
                    else if(c == '*')
                    {
                        p++;
                        for(;; p++)
                        {
                            c = *p;
                          Lcomment:
                            switch(c)
                            {
                            case '*':
                                p++;
                                c = *p;
                                if(c == '/')
                                {
                                    p++;
                                    break;
                                }
                                goto Lcomment;

                            case '\n':
                                currentline++;
                            case '\r':
                                t.sawLineTerminator = p;
                                continue;

                            // case 0:
                            // case 0x1A:
                            //     error(ERR_BAD_C_COMMENT);
                            //     t.value = TOKeof;
                            //     return;

                            default:
                                continue;
                            }
                            break;
                        }
                        continue;
                    }
                    else if(c == '/')
                    {
                        size_t j;
                        d_string test=p[0..end-p];
                        // std.stdio.writefln("p[0..end-p]='%s'",test);
                        foreach(i,r; p[0..end-p]) {
                            //std.stdio.writef("[%s:%04X:%c]",i,r,r);
                            j=i;
                            switch (r) {
                            case '\n':
                                currentline+=1;
                            case '\r', '\0', 0x1A:
                            case '\u2028', '\u2029':
                                t.sawLineTerminator=(p+j);
                                goto LlineTermination;
                            default:
                                /* continue */
                            }
                        }
                      LlineTermination:
                        test=p[0..j];
                        //  std.stdio.writeln(j," comment(",iseval,"='",test,"'");
                        p+=j;
                        continue;
                    }
                    else if((t.string = regexp()) != null) {
                        t.value = TOKregexp;
                    } else
                        t.value = TOKdivide;
                    return;

                case '.':
                    immutable(wchar)* q;
                    q = p + 1;
                    c = *q;
                    if(isdigit(c))
                        t.value = number(t);
                    else
                    {
                        t.value = TOKdot;
                        p = q;
                    }
                    return;

                case '&':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKandass;
                    }
                    else if(c == '&')
                    {
                        p++;
                        t.value = TOKandand;
                    }
                    else
                        t.value = TOKand;
                    return;

                case '|':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKorass;
                    }
                    else if(c == '|')
                    {
                        p++;
                        t.value = TOKoror;
                    }
                    else
                        t.value = TOKor;
                    return;

                case '-':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKminusass;
                    }
                    else if(c == '-')
                    {
                        p++;

                        // If the last token in the file is -. then
                        // treat it as EOF. This is to accept broken
                        // scripts that forgot to protect the closing -.
                        // with a // comment.
                        if(*p == '>')
                        {
                            // Scan ahead to see if it's the last token
                            immutable(wchar)* q;

                            q = p;
                            for(;; )
                            {
                                switch(*++q)
                                {
                                case 0:
                                case 0x1A:
                                    t.value = TOKeof;
                                    p = q;
                                    return;

                                case ' ':
                                case '\t':
                                case '\v':
                                case '\f':
                                case '\n':
                                case '\r':
                                case 0xA0:                  // no-break space
                                    continue;

                                default:
                                    assert(0);
                                }
                            }
                        }
                        t.value = TOKminusminus;
                    }
                    else
                        t.value = TOKminus;
                    return;

                case '+':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKplusass;
                    }
                    else if(c == '+')
                    {
                        p++;
                        t.value = TOKplusplus;
                    }
                    else
                        t.value = TOKplus;
                    return;

                case '<':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKlessequal;
                    }
                    else if(c == '<')
                    {
                        p++;
                        c = *p;
                        if(c == '=')
                        {
                            p++;
                            t.value = TOKshiftleftass;
                        }
                        else
                            t.value = TOKshiftleft;
                    }
                    else if(c == '!' && p[1] == '-' && p[2] == '-')
                    {       // Special comment to end of line
                        p += 2;
                        for(;; )
                        {
                            p++;
                            switch(*p)
                            {
                            case '\n':
                                currentline++;
                            case '\r':
                                t.sawLineTerminator = p;
                                break;

                            case 0:
                            case 0x1A:                              // end of file
                                error(ERR_BAD_HTML_COMMENT);
                                t.value = TOKeof;
                                return;

                            default:
                                continue;
                            }
                            break;
                        }
                        p++;
                        continue;
                    }
                    else
                        t.value = TOKless;
                    return;

                case '>':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKgreaterequal;
                    }
                    else if(c == '>')
                    {
                        p++;
                        c = *p;
                        if(c == '=')
                        {
                            p++;
                            t.value = TOKshiftrightass;
                        }
                        else if(c == '>')
                        {
                            p++;
                            c = *p;
                            if(c == '=')
                            {
                                p++;
                                t.value = TOKushiftrightass;
                            }
                            else
                                t.value = TOKushiftright;
                        }
                        else
                            t.value = TOKshiftright;
                    }
                    else
                        t.value = TOKgreater;
                    return;

                case '(': p++; t.value = TOKlparen;    return;
                case ')': p++; t.value = TOKrparen;    return;
                case '[': p++; t.value = TOKlbracket;  return;
                case ']': p++; t.value = TOKrbracket;  return;
                case '{': p++; t.value = TOKlbrace;    return;
                case '}': p++; t.value = TOKrbrace;    return;
                case '~': p++; t.value = TOKtilde;     return;
                case '?': p++; t.value = TOKquestion;  return;
                case ',': p++; t.value = TOKcomma;     return;
                case ';': p++; t.value = TOKsemicolon; return;
                case ':': p++;
                    t.value = TOKcolon;     return;

                case '*':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKmultiplyass;
                    }
                    else
                        t.value = TOKmultiply;
                    return;

                case '%':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKpercentass;
                    }
                    else
                        t.value = TOKpercent;
                    return;

                case '^':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        t.value = TOKxorass;
                    }
                    else
                        t.value = TOKxor;
                    return;
                case '=':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        c = *p;
                        if(c == '=')
                        {
                            p++;
                            t.value = TOKidentity;
                        }
                        else
                            t.value = TOKequal;
                    }
                    else
                        t.value = TOKassign;
                    return;

                case '!':
                    p++;
                    c = *p;
                    if(c == '=')
                    {
                        p++;
                        c = *p;
                        if(c == '=')
                        {
                            p++;
                            t.value = TOKnonidentity;
                        }
                        else
                            t.value = TOKnotequal;
                    }
                    else
                        t.value = TOKnot;
                    return;

                case '\\':
                    if(p[1] == 'u')
                    {
                        // std.stdio.writeln("unicode 2");
                        // \uXXXX starts an identifier
                        goto Lidentifier2;
                    }
                default:
                    d = *p;
                    if(d >= 0x80 && std.uni.isAlpha(d))
                        goto Lidentifier;
                    else if(isStrWhiteSpaceChar(d))
                    {
                        // = inc(p);            //also skip unicode whitespace
                        if ( *p == '\u2028' || *p == '\u2029' ) {
                            //writeln("linetermination");
                            t.sawLineTerminator = p;
                            p+=1;
                            //goto Llinetermination;
                        }
                        //p+=1;
                        continue;
                    }
                    else
                    {
                        if(isprint(d))
                            error(errmsgtbl[ERR_BAD_CHAR_C], d);
                        else
                            error(errmsgtbl[ERR_BAD_CHAR_X], d);
                    }
                    continue;
                }
            }
        }
    }

    /*******************************************
     * Parse escape sequence.
     */

    wchar escapeSequence()
        {
            wchar c;
            int n;
            uint hexwidth;
            bool octalflag;
            scope(success) {
                if (use_strict && octalflag) {
                    error(ERR_OCTAL_ESC_NOT_ALLOWED);
                }
            }
            c = *p;
            p++;
            switch(c)
            {
            case '\'':
            case '"':
            case '?':
            case '\\':
                break;
// Escape a is not defined in Ecma 262
/*
            case 'a':
                c = 7;

                }
                break;
*/
            case 'b':
                c = 8;
                break;
            case 'f':
                c = 12;
                break;
            case 'n':
                c = 10;
                break;
            case 'r':
                c = 13;
                break;
            case 't':
                c = 9;
                break;

            case 'v':
                version(JSCRIPT_ESCAPEV_BUG)
                {
                }
                else
                {
                    c = 11;
                }
                break;

            case 'x':
                c = *p;
                p++;
                if(ishex(c))
                {
                    uint v;

                    n = 0;
                    v = 0;
                    for(;;)
                    {
                        if(isdigit(c))
                            c -= '0';
                        else if( c>='a' && c<='f' )
                            c -= 'a' - 10;
                        else if( c>='A' && c<='F' )
                            c -= 'A' - 10;
                        else
                            break;
                        v = v * 16 + c;
                        c = *p;
                        if(++n >= 2 || !ishex(c))
                            break;
                        p++;
                    }
                    if(n != 2)
                        error(ERR_BAD_HEX_SEQUENCE);
                    c = cast(wchar)v;
                }
                else
                {
                    wchar[] c_str;
                    c_str~=c;
                    error(errmsgtbl[ERR_UNDEFINED_ESC_SEQUENCE], c_str);
                }
                break;

            default:
                if(c > 0x7F)
                {
                    //p--;
                    c = *(p-1);
                    //p = inc(p);
                }
                //if(isoctal(c))
                if ( c == '0' )
                {
                    octalflag=true;
                    uint v;

                    n = 0;
                    v = 0;
                    for(;; )
                    {
                        v = v * 8 + (c - '0');
                        c = *p;
                        if(++n >= 3 || !isoctal(c))
                            break;
                        p++;
                    }
                    c = cast(wchar)v;
                } else {
                // Don't accept number escape chars ( first char must be '0' )
                    switch ( c ) {
                      case '1':
                      case '2':
                      case '3':
                      case '4':
                      case '5':
                      case '6':
                      case '7':
                      case '8':
                      case '9':
                          wchar[] c_str;
                          c_str~=c;
                          error(errmsgtbl[ERR_UNDEFINED_ESC_SEQUENCE],c_str);
                          break;
                    case 'X':
                        if ( ishex(*p) && ishex(*p) ) {
                            wchar[] c_str;
                            c_str~=r"\X"w; c_str~=p[0]; c_str~=p[1];
                            error(errmsgtbl[ERR_HEX_ESCAPE_SEQUENCE],c_str);
                        }
                        break;
                    case 'U':
                        if ( ishex(*p) && ishex(*(p+1)) && ishex(*(p+2)) && ishex(*(p+3) ) ) {
                            wchar[] c_str;
                            c_str~=r"\U"w;
                            c_str~=p[0..3];
                            error(errmsgtbl[ERR_HEX_ESCAPE_SEQUENCE],c_str);
                        }
                        break;
                    default:
                        // Ignore escape
                    }
                }
                break;
            }
            return c;
        }

    /**************************************
     */

    d_string string(wchar quote)
        {
            wchar c;
//            wchar d;
            d_string stringbuffer;
            // scope(exit) {
            //     std.stdio.writeln(stringbuffer);
            //     foreach(ch;stringbuffer) {
            //         std.stdio.writef("[%04x:%s]",ch,ch);
            //     }
            //     std.stdio.writeln("<");

            // }
            //printf("Lexer.string('%c')\n", quote);
            p++;
            for(;; )
            {
                c = *p;
                switch(c)
                {
                case '"':
                case '\'':
                    p++;
                    if(c == quote)
                        return stringbuffer;
                    break;

                case '\\':
                    p++;
                    if(*p == 'u') {
                        //                       std.stdio.writeln("unicode 3");
                        stringbuffer~=unicode();;
                    } else {
                        // (ignore '\r' '\r\n' ) after esc;
                        switch (*p) {
                        case '\r':
                            p++;
                            if (*p=='\n') p++;
                            break;
                        case '\n':
                            p++;
                            break;
                        default:
                            stringbuffer~=escapeSequence();
                        }
                    }

                    // if (*(p+1) == '\r') {

                        //}

                    // dmdscript.utf.encode(stringbuffer, d);
                    continue;

                case '\n':
                case '\r':
                    p++;
                    error(errmsgtbl[ERR_STRING_NO_END_QUOTE], quote);
                    return null;

                case 0:
                case 0x1A:
                    error(ERR_UNTERMINATED_STRING);
                    return null;

                default:
                    p++;
                    break;
                }
                stringbuffer ~= c;
            }
            assert(0);
        }

    /**************************************
     * Scan regular expression. Return null with buffer
     * pointer intact if it is not a regexp.
     */

    d_string regexp()
        {
            wchar c;
            immutable(wchar)* s;
            immutable(wchar)* start;

            /*
              RegExpLiteral:  RegExpBody RegExpFlags
              RegExpFlags:
              empty
              |  RegExpFlags ContinuingIdentifierCharacter
              RegExpBody:  / RegExpFirstChar RegExpChars /
              RegExpFirstChar:
              OrdinaryRegExpFirstChar
              |  \ NonTerminator
              OrdinaryRegExpFirstChar:  NonTerminator except \ | / | *
              RegExpChars:
              empty
              |  RegExpChars RegExpChar
              RegExpChar:
              OrdinaryRegExpChar
              |  \ NonTerminator
              OrdinaryRegExpChar: NonTerminator except \ | /
            */

            //writefln("Lexer.regexp()\n");
            start = p - 1;
            s = p;

            // Do RegExpBody
            for(;; )
            {
                c = *s;
                s++;
                switch(c)
                {
                case '\\':
                    if(s == p)
                        return null;
                    c = *s;
                    switch(c)
                    {
                    case '\r':
                    case '\n':                      // new line
                    // case 0:                         // end of file
                    // case 0x1A:                      // end of file
                    case '\u2028':
                    case '\u2029':
                        return null;                // not a regexp
                    default:
                        break;
                    }
                    s++;
                    continue;

                case '/':
                    if(s == p + 1)
                        return null;
                    break;

                case '\r':
                case '\n':                          // new line
                case '\u2028':
                case '\u2029':
//                case 0:                             // end of file
//                case 0x1A:                          // end of file
                    return null;                    // not a regexp

                case '*':
                    if(s == p + 1)
                        return null;
                default:
                    continue;
                }
                break;
            }

            //std.stdio.writeln("RegExp=",start[0 .. s - start].idup);
            // Do RegExpFlags
            for(;; )
            {
                c = *s;

                if (isalnum(c) || c == '_' || c == '$')
                {
                    s++;
                }
                else
                    break;
            }

            // Finish pattern & return it
            p = s;
            return start[0 .. s - start].idup;
        }

    /***************************************
     */

    wchar unicode()
        {
            wchar value;
            uint n;
            wchar c;

            value = 0;
            p++;
            // std.stdio.writefln("in u%s", p[0..4]);
            for(n = 0; n < 4; n++)
            {
                c = *p;
                if(!ishex(c))
                {
                    error(ERR_BAD_U_SEQUENCE);
                    break;
                }
                p++;
                if(isdigit(c))
                    c -= '0';
                else if(isasciilower(c))
                    c -= 'a' - 10;
                else    // 'A' <= c && c <= 'Z'
                    c -= 'A' - 10;
                value <<= 4;
                value |= c;
            }
            //std.stdio.writefln("out %04x",value);
            return value;
        }

    /********************************************
     * Read a number.
     */

    TOK number(Token *t) {
        immutable(wchar)* start;
        number_t intvalue;
        real realvalue;
        int base = 10;
        wchar c;
        scope(success) {
            if ( use_strict && (base == 8) && ( (intvalue != 0) || (p - start) > 1) )  {
                error(ERR_OCTAL_NOT_ALLOWED);
            }
        }
        with(TOK) {
            start = p;
            for(;; )
            {
                c = *p;
                p++;

                switch(c)
                {
                case '0':
                    // ECMA grammar implies that numbers with leading 0
                    // like 015 are illegal. But other scripts allow them.
                    if(p - start == 1)  {             // if leading 0
                        base = 8;
                    }
                case '1': case '2': case '3': case '4': case '5':
                case '6': case '7':
                    break;

                case '8': case '9':                         // decimal digits
                    if(base == 8)                           // and octal base
                        base = 10;                          // means back to decimal base
                    break;

                default:
                    p--;
                Lnumber:
                    if(base == 0)
                        base = 10;
                    intvalue = 0;
                    if ( base == 10 && p - start > 20 )
                    { // maybe too big to be number_t
                        goto Ldouble;
                    }
                    foreach(wchar v; start[0 .. p - start])
                    {
                        if('0' <= v && v <= '9')
                            v -= '0';
                        else if('a' <= v && v <= 'f')
                            v -= ('a' - 10);
                        else if('A' <= v && v <= 'F')
                            v -= ('A' - 10);
                        else
                            assert(0);
                        assert(v < base);
                        if((number_t.max - v) / base < intvalue)
                        {

                            realvalue = 0;
                            foreach(wchar w; start[0 .. p - start])
                            {
                                if('0' <= w && w <= '9')
                                    w -= '0';
                                else if('a' <= w && w <= 'f')
                                    w -= ('a' - 10);
                                else if('A' <= w && w <= 'F')
                                    w -= ('A' - 10);
                                else
                                    assert(0);
                                 realvalue *= base;
                                realvalue += w;
                            }
                            t.realvalue = realvalue;
                            return TOKreal;
                        }
                        intvalue *= base;
                        intvalue += v;
                    }
                    t.realvalue = cast(double)intvalue;
                    return TOKreal;

                case 'x':
                case 'X':
                    if(p - start != 2 || !ishex(*p))
                        goto Lerr;
                    do
                        p++;
                    while(ishex(*p));
                    start += 2;
                    base = 16;
                    goto Lnumber;

                case '.':
                    while(isdigit(*p))
                        p++;
                    if(*p == 'e' || *p == 'E')
                    {
                        p++;
                        goto Lexponent;
                    }
                    goto Ldouble;

                case 'e':
                case 'E':
                Lexponent:
                    if(*p == '+' || *p == '-')
                        p++;
                    if(!isdigit(*p))
                        goto Lerr;
                    do
                        p++;
                    while(isdigit(*p));
                    goto Ldouble;

                Ldouble:
                    // convert double
                    immutable(char)[] str=fromDstring(start[0..p-start]);
                    realvalue = std.c.stdlib.strtod(std.string.toStringz(str), null);
                    //realvalue = dmdscript.value.Value.stringToNumber(start[0 .. p - start]);
                    t.realvalue = realvalue;
                    return TOKreal;
                }
            }
        }
      Lerr:
        error(ERR_UNRECOGNIZED_N_LITERAL);
        return TOK.TOKeof;
    }

    TOK isKeyword(const (wchar)[] s) {
        TOK _isKeyword()
        {
            with(TOK) {
                if(s[0] >= 'a' && s[0] <= 'y'  && (!keyword_as_property) )
                    switch(s.length)
                    {
                    case 2:
                        if(s[0] == 'i')
                        {
                            if(s[1] == 'f')
                                return TOKif;
                            if(s[1] == 'n')
                                return TOKin;
                        }
                        else if(s[0] == 'd' && s[1] == 'o')
                            return TOKdo;
                        break;

                    case 3:
                        switch(s[0])
                        {
                        case 'f':
                            if(s[1] == 'o' && s[2] == 'r')
                                return TOKfor;
                            break;
                        case 'i':
                            if(s[1] == 'n' && s[2] == 't')
                                return TOKint;
                            break;
                        case 'n':
                            if(s[1] == 'e' && s[2] == 'w')
                                return TOKnew;
                            break;
                        case 't':
                            if(s[1] == 'r' && s[2] == 'y')
                                return TOKtry;
                            break;
                        case 'v':
                            if(s[1] == 'a' && s[2] == 'r')
                                return TOKvar;
                        case 'l':
                            if(s[1] == 'e' && s[2] == 't')
                                return TOKlet;
                            break;
                        default:
                            break;
                        }
                        break;

                    case 4:
                        switch(s[0])
                        {
                        case 'b':
                            if(s[1] == 'y' && s[2] == 't' && s[3] == 'e')
                                return TOKbyte;
                            break;
                        case 'c':
                            if(s[1] == 'a' && s[2] == 's' && s[3] == 'e')
                                return TOKcase;
                            if(s[1] == 'h' && s[2] == 'a' && s[3] == 'r')
                                return TOKchar;
                            break;
                        case 'e':
                            if(s[1] == 'l' && s[2] == 's' && s[3] == 'e')
                                return TOKelse;
                            if(s[1] == 'n' && s[2] == 'u' && s[3] == 'm')
                                return TOKenum;
                            break;
                        case 'g':
                            if(s[1] == 'o' && s[2] == 't' && s[3] == 'o')
                                return TOKgoto;
                            break;
                        case 'l':
                            if(s[1] == 'o' && s[2] == 'n' && s[3] == 'g')
                                return TOKlong;
                            break;
                        case 'n':
                            if(s[1] == 'u' && s[2] == 'l' && s[3] == 'l')
                                return TOKnull;
                            break;
                        case 't':
                            if(s[1] == 'h' && s[2] == 'i' && s[3] == 's')
                                return TOKthis;
                            if(s[1] == 'r' && s[2] == 'u' && s[3] == 'e')
                                return TOKtrue;
                            break;
                        case 'w':
                            if(s[1] == 'i' && s[2] == 't' && s[3] == 'h')
                                return TOKwith;
                            break;
                        case 'v':
                            if(s[1] == 'o' && s[2] == 'i' && s[3] == 'd')
                                return TOKvoid;
                            break;
                        default:
                            break;
                        }
                        break;

                    case 5:
                        switch(s)
                        {
                        case "break":               return TOKbreak;
                        case "catch":               return TOKcatch;
                        case "class":               return TOKclass;
                        case "const":               return TOKconst;
                        case "false":               return TOKfalse;
                        case "final":               return TOKfinal;
                        case "float":               return TOKfloat;
                        case "short":               return TOKshort;
                        case "super":               return TOKsuper;
                        case "throw":               return TOKthrow;
                        case "while":               return TOKwhile;
                        case "yield":               return TOKyield;
                        default:
                            break;
                        }
                        break;

                    case 6:
                        switch(s)
                        {
                        case "delete":              return TOKdelete;
                        case "double":              return TOKdouble;
                        case "export":              return TOKexport;
                        case "import":              return TOKimport;
                        case "native":              return TOKnative;
                        case "public":              return TOKpublic;
                        case "return":              return TOKreturn;
                        case "static":              return TOKstatic;
                        case "switch":              return TOKswitch;
                        case "throws":              return TOKthrows;
                        case "typeof":              return TOKtypeof;
                        default:
                            break;
                        }
                        break;

                    case 7:
                        switch(s)
                        {
                        case "boolean":             return TOKboolean;
                        case "default":             return TOKdefault;
                        case "extends":             return TOKextends;
                        case "finally":             return TOKfinally;
                        case "package":             return TOKpackage;
                        case "private":             return TOKprivate;
                        default:
                            break;
                        }
                        break;

                    case 8:
                        switch(s)
                        {
                        case "abstract":    return TOKabstract;
                        case "continue":    return TOKcontinue;
                        case "debugger":    return TOKdebugger;
                        case "function":    return TOKfunction;
                        default:
                            break;
                        }
                        break;

                    case 9:
                        switch(s)
                        {
                        case "interface":   return TOKinterface;
                        case "protected":   return TOKprotected;
                        case "transient":   return TOKtransient;
                        default:
                            break;
                        }
                        break;

                    case 10:
                        switch(s)
                        {
                        case "implements":  return TOKimplements;
                        case "instanceof":  return TOKinstanceof;
                        default:
                            break;
                        }
                        break;

                    case 12:
                        if(s == "synchronized")
                            return TOKsynchronized;
                        break;

                    default:
                        break;
                    }
                return TOKreserved;             // not a keyword
            }
        }
        TOK result=_isKeyword();
        version(Ecmascript5) {
            if ( use_strict )
                return Token.ES5StrictModeReserved(result);
            else
                return Token.ES5Reserved(result);
        } else {
            return result;
        }
    }
    static bool strictToken(const(Token) token) {
        return token.string == TEXT_use_strict;
    }
}


/****************************************
 */

// Keyword category
enum Category {
    None = 0,
    Symbol         = 0b0000_0001, // Non command keyword
    Used           = 0b0000_0010, // Keyword which is used in Ecmascript
    Obsolete       = 0b0000_0100, // Obsoleted keyword from Ecmascipt 3
    Reserved       = 0b0000_1000, // Reserved keyword (no function)
    NewReserved    = 0b0001_0000, // Reseved word added to Ecmascript 5
    FutureReserved = 0b0010_0000, // Future reserved keywords
};

struct Keyword
{
    d_string   name;
    TOK      value;
    Category category;
}

static Keyword[d_string] akeyword;

static Keyword[] keywords =
    [
        { "break", TOK.TOKbreak, Category.Used },
        { "case", TOK.TOKcase, Category.Used },
        { "continue", TOK.TOKcontinue, Category.Used },
        { "default", TOK.TOKdefault, Category.Used },
        { "delete", TOK.TOKdelete, Category.Used },
        { "do", TOK.TOKdo, Category.Used },
        { "else", TOK.TOKelse, Category.Used },

        { "false", TOK.TOKfalse, Category.Used },
        { "for", TOK.TOKfor, Category.Used },
        { "function", TOK.TOKfunction, Category.Used },
        { "if", TOK.TOKif, Category.Used },

        { "in", TOK.TOKin, Category.Used },
        { "new", TOK.TOKnew, Category.Used },
        { "null", TOK.TOKnull, Category.Used },
        { "return", TOK.TOKreturn, Category.Used },
        { "switch", TOK.TOKswitch,Category.Used },
        { "this", TOK.TOKthis, Category.Used },
        { "true", TOK.TOKtrue, Category.Used },
        { "typeof", TOK.TOKtypeof, Category.Used },
        { "var", TOK.TOKvar, Category.Used },
        { "void", TOK.TOKvoid, Category.Used },
        { "while", TOK.TOKwhile, Category.Used },
        { "with", TOK.TOKwith, Category.Used },
        { "catch", TOK.TOKcatch, Category.Used },


        { "debugger", TOK.TOKdebugger, Category.Used },


        { "finally", TOK.TOKfinally, Category.Used },

        { "throw", TOK.TOKthrow, Category.Used },
        { "try", TOK.TOKtry, Category.Used },
        { "instanceof", TOK.TOKinstanceof, Category.Used },

        { "abstract", TOK.TOKabstract, Category.Obsolete },
        { "boolean", TOK.TOKboolean, Category.Obsolete },
        { "byte", TOK.TOKbyte, Category.Obsolete },
        { "char", TOK.TOKchar, Category.Obsolete },
        { "double", TOK.TOKdouble, Category.Obsolete },
        { "final", TOK.TOKfinal, Category.Obsolete },
        { "float", TOK.TOKfloat, Category.Obsolete },
        { "goto", TOK.TOKgoto, Category.Obsolete },
        { "int", TOK.TOKint, Category.Obsolete },
        { "interface", TOK.TOKinterface, Category.Obsolete | Category.FutureReserved },
        { "long", TOK.TOKlong, Category.Obsolete },
        { "native", TOK.TOKnative, Category.Obsolete },
        { "package", TOK.TOKpackage, Category.Obsolete | Category.FutureReserved },
        { "protected", TOK.TOKprotected, Category.Obsolete | Category.FutureReserved },
        { "public", TOK.TOKpublic, Category.Obsolete | Category.FutureReserved },
        { "short", TOK.TOKshort, Category.Obsolete },
        { "static", TOK.TOKstatic, Category.Obsolete | Category.FutureReserved },
        { "synchronized", TOK.TOKsynchronized, Category.Obsolete },
        { "throws", TOK.TOKthrows, Category.Obsolete },
        { "transient", TOK.TOKtransient, Category.Obsolete },

        { "class", TOK.TOKclass, Category.Reserved },
        { "const", TOK.TOKconst, Category.Reserved },
        { "enum", TOK.TOKenum, Category.Reserved },
        { "export", TOK.TOKexport, Category.Reserved },
        { "extends", TOK.TOKextends, Category.Reserved },
        { "import", TOK.TOKimport, Category.Reserved },
        { "super", TOK.TOKsuper, Category.Reserved },

        { "implements", TOK.TOKimplements, Category.FutureReserved },
        { "let", TOK.TOKlet, Category.FutureReserved },
        { "private", TOK.TOKprivate, Category.FutureReserved },
        { "public", TOK.TOKpublic, Category.FutureReserved },
        { "yield", TOK.TOKyield, Category.FutureReserved },

        { "interface", TOK.TOKinterface, Category.FutureReserved },
        { "package", TOK.TOKpackage, Category.FutureReserved },
        { "protected", TOK.TOKprotected, Category.FutureReserved },
        { "static", TOK.TOKstatic, Category.FutureReserved },
        ];
