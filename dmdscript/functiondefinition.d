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


module dmdscript.functiondefinition;

import std.stdio;

import dmdscript.script;
import dmdscript.identifier;
import dmdscript.statement;
import dmdscript.dfunction;
import dmdscript.scopex;
import dmdscript.irstate;
import dmdscript.opcodes;
import dmdscript.ddeclaredfunction;
import dmdscript.symbol;
import dmdscript.dobject;
import dmdscript.ir;
import dmdscript.errmsgs;
import dmdscript.value;
import dmdscript.property;
import dmdscript.expression;

/* ========================== FunctionDefinition ================== */

class FunctionDefinition : Statement
{
    // Maybe the following two should be done with derived classes instead
    int isglobal;                 // !=0 if the global anonymous function
    int isliteral;                // !=0 if function literal
    bool iseval;                  // true if eval function
    bool strict_mode;             // true if the function is in strict mode

    Identifier* name;             // null for anonymous function
    Identifier*[] parameters;     // array of Identifier's
    TopStatement[] topstatements; // array of TopStatement's

    Identifier*[] varnames;       // array of Identifier's
    FunctionDefinition[] functiondefinitions;
    FunctionDefinition enclosingFunction;
    int nestDepth;
    int withdepth;              // max nesting of ScopeStatement's

    SymbolTable *labtab;        // symbol table for LabelSymbol's

    IR *code;
    uint nlocals;

    d_string source;            // Source as text
    d_string sourceid;          // Name of the source code
    this(TopStatement[] topstatements)
    {
        super(0);
        st = d_statement.FUNCTIONDEFINITION;
        this.isglobal = 1;
        this.topstatements = topstatements;
    }

    this(Loc loc, int isglobal,
         Identifier * name, Identifier *[] parameters,
         TopStatement[] topstatements)
    {
        super(loc);

        //writef("FunctionDefinition('%ls')\n", name ? name.string : L"");
        st = d_statement.FUNCTIONDEFINITION;
        this.isglobal = isglobal;
        this.name = name;
        this.parameters = parameters;
        this.topstatements = topstatements;
    }

    int isAnonymous() { return name is null; }

    override Statement semantic(Scope *sc)
    {
        uint i;
        TopStatement ts;
        FunctionDefinition fd;

        //writef("FunctionDefinition::semantic(%s)\n", this);

        // Log all the FunctionDefinition's so we can rapidly
        // instantiate them at runtime
        fd = enclosingFunction = sc.funcdef;

        // But only push it if it is not already in the array
        for(i = 0;; i++)
        {
            if(i == fd.functiondefinitions.length)      // not in the array
            {
                fd.functiondefinitions ~= this;
                break;
            }
            if(fd.functiondefinitions[i] is this)       // already in the array
                break;
        }

        //writefln("isglobal = %d, isanonymous = %d\n", isglobal, isanonymous);
        if(!isglobal)
        {
            sc = sc.push(this);
            sc.nestDepth++;
        }
        nestDepth = sc.nestDepth;
        //writefln("nestDepth = %d", nestDepth);

        if(topstatements.length)
        {
            for(i = 0; i < topstatements.length; i++)
            {
                ts = topstatements[i];
                //writefln("calling semantic routine %d which is %x\n",i, cast(uint)cast(void*)ts);
                if(!ts.done)
                {
                    ts = ts.semantic(sc);
                    if(sc.errinfo.message)
                        break;
                    if(iseval)
                    {
                        // There's an implied "return" on the last statement
                        if((i + 1) == topstatements.length)
                        {
                            ts = ts.ImpliedReturn();
                        }
                    }
                    topstatements[i] = ts;
                    ts.done = 1;
                }
            }

            // Make sure all the LabelSymbol's are defined
            if(labtab)
            {
                foreach(Symbol s; labtab.members)
                {
                    LabelSymbol ls = cast(LabelSymbol)s;
                    if(!ls.statement)
                        error(sc, errmsgtbl[ERR_UNDEFINED_LABEL],
                              ls.toText, toString);
                }
            }
        }

        if(!isglobal)
            sc.pop();

        FunctionDefinition fdx = this;
        return cast(Statement)fdx;
    }

    override void toBuffer(ref wchar[] buf)
    {
        uint i;

        //writef("FunctionDefinition::toBuffer()\n");
        if(!isglobal) {
            buf ~= "function "w;
            if(isAnonymous)
                buf ~= ""w;
            else if(name)
                buf ~= name.toText;
            buf ~= '(';
            for(i = 0; i < parameters.length; i++)
            {
                if(i)
                    buf ~= ',';
                buf ~= parameters[i].toText;
            }
            buf ~= ") {"w;
        }
        if (source) {
            buf ~=source;
        } else {
            buf ~= "\n"w;
            if(topstatements)
            {
                for(i = 0; i < topstatements.length; i++)
                {
                    topstatements[i].toBuffer(buf);
                }
            }
        }
        if(!isglobal)
        {
            buf ~= "}\n"w;
        }
    }

    override void toIR(IRstate *ignore)
    {
        IRstate irs;
        IRstate tmp_irs;
        uint i;
        FunctionDefinition lastfd;

        irs.ctor();
        if(topstatements.length)
        {
            for(i = 0; i < topstatements.length; i++)
            {
                TopStatement ts;
                FunctionDefinition fd;

                ts = topstatements[i];
                if(ts.st == d_statement.FUNCTIONDEFINITION)
                {
                    fd = cast(FunctionDefinition)ts;
                    lastfd = fd;
                    if(fd.code)
                        continue;
                }

                ts.toIR(&irs);

            }

            // Don't need parse trees anymore, release to garbage collector
            topstatements[] = null;
            topstatements = null;
            labtab = null;                      // maybe delete it?
        }
        if (lastfd && iseval) {
            // If the last statement in a function is an anonymous
            // function then return this function
            uint e = irs.alloc(1);
            irs.gen2(loc, IRcode.IRobject, e, cast(size_t)cast(void*)lastfd);
            irs.gen1(0, IRcode.IRimpret, e);

        }
        irs.gen0(0, IRcode.IRret);
        irs.gen0(0, IRcode.IRend);


        //irs.validate();
        irs.doFixups();
        irs.optimize();

        code = cast(IR *)irs.codebuf.data;
        irs.codebuf.data = null;
        nlocals = irs.getNlocals;
    }

    void instantiate(Dobject[] scopex, Dobject actobj, ushort attributes)
    {
        //writefln("FunctionDefinition.instantiate() %s nestDepth = %d", name ? name.toText : "", nestDepth);

        // Instantiate all the Var's per 10.1.3
        foreach(Identifier* name; varnames)
        {
            // If name is already declared, don't override it
            //writefln("\tVar Put(%s)", name.toText);
            actobj.Put(name.toText, &Value.vundefined, Instantiate | DontConfig | attributes);
        }

        // Instantiate the Function's per 10.1.3
        foreach(FunctionDefinition fd; functiondefinitions)
        {
            // Set [[Scope]] property per 13.2 step 7
            Dfunction fobject = new DdeclaredFunction(fd);
            fobject.scopex = scopex;

            if(fd.name !is null && !fd.isliteral)        // skip anonymous functions
            {
                //writefln("\tFunction Put(%s)", fd.name.toText);
                actobj.Put(fd.name.toText, fobject, Instantiate | attributes);
            }
        }
        //writefln("-FunctionDefinition.instantiate()");
    }
}
