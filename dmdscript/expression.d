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

module dmdscript.expression;

import std.string;
import std.algorithm;
import std.range;
import std.exception;
import std.stdio;

import dmdscript.script;
import dmdscript.lexer;
import dmdscript.scopex;
import dmdscript.text;
import dmdscript.errmsgs;
import dmdscript.functiondefinition;
import dmdscript.irstate;
import dmdscript.ir;
import dmdscript.opcodes;
import dmdscript.identifier;

alias std.ascii.isPrintable isprint;

/******************************** Expression **************************/



class Expression : ScriptType
{
    enum uint EXPRESSION_SIGNATURE = 0x3AF31E3F;
    uint signature = EXPRESSION_SIGNATURE;

    Loc loc;                    // file location
    TOK op;
    d_string source;

    this(Loc loc, TOK op)
    {
        this.loc = loc;
        this.op = op;
        signature = EXPRESSION_SIGNATURE;
    }

    invariant()
    {
        assert(signature == EXPRESSION_SIGNATURE);
        assert(op != TOK.TOKreserved && op < TOK.max);
    }

    /**************************
     * Semantically analyze Expression.
     * Determine types, fold constants, e
     */

    Expression semantic(Scope *sc)
    {
        return this;
    }

    override d_string toText()
    {
        wchar[] buf;

        toBuffer(buf);
        return assumeUnique(buf);
    }

    void toBuffer(ref wchar[] buf)
    {
        buf ~= toText;
    }

    void checkLvalue(Scope *sc)
    {
        d_string buf;

        //writefln("checkLvalue(), op = %d", op);
        if(sc.funcdef)
        {
            if(sc.funcdef.isAnonymous)
                buf = "anonymous";
            else if(sc.funcdef.name)
                buf = sc.funcdef.name.toText;
        }
        buf ~= dmdscript.script.format("(%d) : Error: ", loc);
        buf ~= dmdscript.script.format(errmsgtbl[ERR_CANNOT_ASSIGN_TO], toText);

        if(!sc.errinfo.message)
        {
            sc.errinfo.etype=error_type_t.referenceerror;
            sc.errinfo.message = buf;
            sc.errinfo.linnum = loc;
            sc.errinfo.srcline = Lexer.locToSrcLine(sc.getSource().ptr, loc);
        }
    }

    // Do we match for purposes of optimization?

    int match(Expression e)
    {
        return false;
    }

    // Is the result of the expression guaranteed to be a boolean?

    int isBooleanResult()
    {
        return false;
    }

    void toIR(IRstate *irs, unsigned ret)
    {
        writef("Expression::toIR('%s')\n", toText);
    }

    void toLvalue(IRstate *irs, out unsigned base, IR *property, out int opoff)
    {
        base = irs.alloc(1);
        toIR(irs, base);
        property.index = 0;
        opoff = 3;
    }
}

/******************************** RealExpression **************************/

class RealExpression : Expression
{
    real_t value;

    this(Loc loc, real_t value)
    {
        super(loc, TOK.TOKreal);
        this.value = value;
    }

    override d_string toText()
    {
        return dmdscript.value.Value.numberToString(value);
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= dmdscript.value.Value.numberToString(value);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
      //writef("RealExpression::toIR(%g)\n", value);
	version(D_LP64)
	  static assert(value.sizeof == unsigned.sizeof);
	else
	  static assert(value.sizeof == 2 * uint.sizeof);
        if(ret) {
		  version(D_LP64)
			irs.gen2(loc, IRcode.IRnumber, ret, value);
		  else
		    irs.gen(loc, IRcode.IRnumber, 3, ret, value);
		}
    }
}

/******************************** IdentifierExpression **************************/

class IdentifierExpression : Expression
{
    Identifier *ident;

    this(Loc loc, Identifier * ident)
    {
        super(loc, TOK.TOKidentifier);
        this.ident = ident;
    }

    override Expression semantic(Scope *sc)
    {
        return this;
    }

    override d_string toText()
    {
        return ident.toText;
    }

    override void checkLvalue(Scope *sc)
    {
    }

    override int match(Expression e)
    {
        if(e.op != TOK.TOKidentifier)
            return 0;

        IdentifierExpression ie = cast(IdentifierExpression)(e);

        return ident == ie.ident;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        Identifier* id = ident;

        assert(id.sizeof == unsigned.sizeof);
        if(ret)
            irs.gen2(loc, IRcode.IRgetscope, ret, cast(unsigned)id);
        else
            irs.gen1(loc, IRcode.IRcheckref, cast(unsigned)id);
    }

    override void toLvalue(IRstate *irs, out unsigned base, IR *property, out int opoff)
    {
        //irs.gen1(loc, IRthis, base);
        property.id = ident;
        opoff = 2;
        base = ~0u;
    }
}

/******************************** ThisExpression **************************/

class ThisExpression : Expression
{
    this(Loc loc)
    {
        super(loc, TOK.TOKthis);
    }

    override d_string toText()
    {
        return TEXT_this;
    }

    override Expression semantic(Scope *sc)
    {
        return this;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        if(ret)
            irs.gen1(loc, IRcode.IRthis, ret);
    }
}

/******************************** NullExpression **************************/

class NullExpression : Expression
{
    this(Loc loc)
    {
        super(loc, TOK.TOKnull);
    }

    override d_string toText()
    {
        return TEXT_null;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        if(ret)
            irs.gen1(loc, IRcode.IRnull, ret);
    }
}

/******************************** StringExpression **************************/

class StringExpression : Expression
{
    d_string string;
    bool first_command_in_block;

    this(Loc loc, d_string string, bool first_command_in_block=false)
    {
        //writefln("StringExpression('%s')", string);
        super(loc, TOK.TOKstring);
        this.string = string;
        this.first_command_in_block=first_command_in_block;
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= '"';
        foreach(c; string)
        {
            switch(c)
            {
            case '"':
                buf ~= '\\';
                goto Ldefault;

            default:
                Ldefault:
                if(c & ~0xFF)
                    buf ~= dmdscript.script.format("\\u%04x", c);
                else if(isprint(c))
                    buf ~= c;
                else
                    buf ~= dmdscript.script.format("\\x%02x", c);
                break;
            }
        }
        buf ~= '"';
    }

    override void toIR(IRstate *irs, unsigned ret) {
        static assert((Identifier*).sizeof == unsigned.sizeof);
        //writefln("IRstring '%s' ret=%d",string,ret);
        if(ret)
        {
            unsigned u = cast(unsigned)Identifier(string);
            irs.gen2(loc, IRcode.IRstring, ret, u);
        }
        else {// Possible strict mode
            version(Ecmascript5) {
                //  std.stdio.writeln("loc=",loc," first_command_in_block=",first_command_in_block);
                if (first_command_in_block && (string == TEXT_use_strict) ) {
                    irs.gen1(loc, IRcode.IRuse_strict, 1);
                } else if ( (string.length > TEXT_use_strict.length) && (string[0..TEXT_use_strict.length] == TEXT_use_strict) ) {
                    d_string cmd=string[TEXT_use_strict.length..$];
                    while (cmd.length !is 0 && cmd[0]==' ') cmd=cmd[1..$];
                    switch(cmd) {
                    case "on":
                        std.stdio.writeln("IR Strict ->on");
                        irs.gen1(loc, IRcode.IRuse_strict, 1);
                        break;
                    case "off":
                        std.stdio.writeln("IR Strict ->off");

                        irs.gen1(loc, IRcode.IRuse_strict, 0);
                        break;
                    case "clear":
                        std.stdio.writeln("IR Strict ->clear");

                        irs.gen1(loc, IRcode.IRuse_strict, 2);
                        break;
                    case "restore":
                        std.stdio.writeln("IR Strict ->restore");

                        irs.gen1(loc, IRcode.IRuse_strict, 3);
                        break;
                    default:
                        std.stdio.writeln("IR Strict ->UNKNOWN");

                        /* empty */
                    }
                } else if ( (string.length >= TEXT_use_trace.length) && (string[0..TEXT_use_trace.length] == TEXT_use_trace) ) {
                    d_string cmd=string[TEXT_use_trace.length..$];
//              std.stdio.writeln("trace=",string);
                    while (cmd.length !is 0  && cmd[0]==' ') cmd=cmd[1..$];
                    switch (cmd) {
                    case "on":
                        std.stdio.writeln("On");
                        irs.gen1(loc, IRcode.IRuse_trace, 1);
                        break;
                    case "off":
                        std.stdio.writeln("Off");
                        irs.gen1(loc, IRcode.IRuse_trace, 0);
                        break;
                    default:
                        /* empty */
                    }
                } else {
                    writefln("NOT 'use strict mode' '%s' ",string);
                }
            }
        }
    }
}

/******************************** RegExpLiteral **************************/

class RegExpLiteral : Expression
{
    d_string string;

    this(Loc loc, d_string string)
    {
        //writefln("RegExpLiteral('%s')", string);
        super(loc, TOK.TOKregexp);
        this.string = string;
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= string;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        d_string pattern;
        d_string attribute = null;
        int e;

        uint argc;
        uint argv;
        uint b;

        // Regular expression is of the form:
        //	/pattern/attribute

        // Parse out pattern and attribute strings
        assert(string[0] == '/');
        e = cast(int)std.string.lastIndexOf(string, '/');
        assert(e != -1);
        pattern = string[1 .. e];
        argc = 1;
        if(e + 1 < string.length)
        {
            attribute = string[e + 1 .. $];
            argc++;
        }

        // Generate new Regexp(pattern [, attribute])

        b = irs.alloc(1);
        Identifier* re = Identifier(TEXT_RegExp);
        irs.gen2(loc, IRcode.IRgetscope, b, cast(unsigned)re);
        argv = irs.alloc(argc);
        irs.gen2(loc, IRcode.IRstring, argv, cast(unsigned)Identifier(pattern));
        if(argc == 2)
            irs.gen2(loc, IRcode.IRstring, argv + 1 * INDEX_FACTOR, cast(unsigned)Identifier(attribute));
        irs.gen4(loc, IRcode.IRnew, ret, b, argc, argv);
        irs.release(b, argc + 1);
    }
}

/******************************** BooleanExpression **************************/

class BooleanExpression : Expression
{
    int boolean;

    this(Loc loc, int boolean)
    {
        super(loc, TOK.TOKboolean);
        this.boolean = boolean;
    }

    override d_string toText()
    {
        return boolean ? "true" : "false";
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= toText;
    }

    override int isBooleanResult()
    {
        return true;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        if(ret)
            irs.gen2(loc, IRcode.IRboolean, ret, boolean);
    }
}

/******************************** ArrayLiteral **************************/

class ArrayLiteral : Expression
{
    Expression[] elements;

    this(Loc loc, Expression[] elements)
    {
        super(loc, TOK.TOKarraylit);
        this.elements = elements;
    }

    override Expression semantic(Scope *sc)
    {
        foreach(ref Expression e; elements)
        {
            if(e)
                e = e.semantic(sc);
        }
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        uint i;

        buf ~= '[';
        foreach(Expression e; elements)
        {
            if(i)
                buf ~= ',';
            i = 1;
            if(e)
                e.toBuffer(buf);
        }
        buf ~= ']';
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint argc;
        uint argv;
        uint b;
        uint v;

        b = irs.alloc(1);
        static Identifier* ar;
        if(!ar)
            ar = Identifier(TEXT_Array);
        irs.gen2(loc, IRcode.IRgetscope, b, cast(unsigned)ar);
        if(elements.length)
        {
            Expression e;

            argc = cast(uint)elements.length;
            argv = irs.alloc(argc);
            if(argc > 1)
            {
                uint i;

                // array literal [a, b, c] is equivalent to:
                //	new Array(a,b,c)
                for(i = 0; i < argc; i++)
                {
                    e = elements[i];
                    if(e)
                    {
                        e.toIR(irs, argv + i * INDEX_FACTOR);
                    }
                    else
                        irs.gen1(loc, IRcode.IRundefined, argv + i * INDEX_FACTOR);
                }
                irs.gen4(loc, IRcode.IRnew, ret, b, argc, argv);
            }
            else
            {   //	[a] translates to:
                //	ret = new Array(1);
                //  ret[0] = a
	      version(D_LP64)
		version (DigitalMars)
		  irs.gen2(loc, IRcode.IRnumber, argv, 1.0);
	        else
		  irs.gen(loc, IRcode.IRnumber, 2, argv, 1.0);
	      else
                irs.gen(loc, IRcode.IRnumber, 3, argv, 1.0);
                irs.gen4(loc, IRcode.IRnew, ret, b, argc, argv);

                e = elements[0];
                v = irs.alloc(1);
                if(e)
                    e.toIR(irs, v);
                else
                    irs.gen1(loc, IRcode.IRundefined, v);
                irs.gen3(loc, IRcode.IRputs, v, ret, cast(unsigned)Identifier(TEXT_0));
                irs.release(v, 1);
            }
            irs.release(argv, argc);
        }
        else
        {
            // Generate new Array()
            irs.gen4(loc, IRcode.IRnew, ret, b, 0, 0);
        }
        irs.release(b, 1);
    }
}

/******************************** FieldLiteral **************************/

class Field
{
    Identifier* ident;
    Expression exp;
    enum type_t : uint {
        property=1<<0,
        setter  =1<<1,
        getter  =1<<2
    };
    type_t type;

    this(Identifier * ident, Expression exp, type_t type)
    {
        this.ident = ident;
        this.exp = exp;
        this.type = type;
    }
}

/******************************** ObjectLiteral **************************/

class ObjectLiteral : Expression
{
    Field[] fields;

    this(Loc loc, Field[] fields)
    {
        super(loc, TOK.TOKobjectlit);
        this.fields = fields;
    }

    override Expression semantic(Scope *sc)
    {
        foreach(Field f; fields)
        {
            f.exp = f.exp.semantic(sc);
        }
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        uint i;

        buf ~= '{';
        foreach(Field f; fields)
        {
            if(i)
                buf ~= ',';
            i = 1;
            buf ~= f.ident.toText;
            buf ~= ':';
            f.exp.toBuffer(buf);
        }
        buf ~= '}';
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint b;

        b = irs.alloc(1);
        //irs.gen2(loc, IRstring, b, TEXT_Object);
        Identifier* ob = Identifier(TEXT_Object);
        irs.gen2(loc, IRcode.IRgetscope, b, cast(unsigned)ob);
        // Generate new Object()
        irs.gen4(loc, IRcode.IRnew, ret, b, 0, 0);
        if(fields.length)
        {
            uint x;

            x = irs.alloc(1);
            foreach(Field f; fields)
            {
                f.exp.toIR(irs, x);
                with(f) final switch(type) {
                    case type_t.property:
                        irs.gen3(loc, IRcode.IRputs, x, ret, cast(unsigned)(f.ident));
                        break;
                    case type_t.setter:
                        irs.gen3(loc, IRcode.IRputSet, x, ret, cast(unsigned)(f.ident));
                        break;
                    case type_t.getter:
                        irs.gen3(loc, IRcode.IRputGet, x, ret, cast(unsigned)(f.ident));
                        break;

                    }
            }
        }
    }
}

/******************************** FunctionLiteral **************************/

class FunctionLiteral : Expression
{ FunctionDefinition func;

  this(Loc loc, FunctionDefinition func)
  {
      super(loc, TOK.TOKobjectlit);
      this.func = func;
      this.source = func.source;
  }

  override Expression semantic(Scope *sc)
  {
      func = cast(FunctionDefinition)(func.semantic(sc));
      return this;
  }

  override void toBuffer(ref wchar[] buf)
  {
      func.toBuffer(buf);
  }

  override void toIR(IRstate *irs, unsigned ret)
  {
      func.source=source; // Set the source code
      func.toIR(null);
      irs.gen2(loc, IRcode.IRobject, ret, cast(size_t)cast(void*)func);
  }
}

/***************************** UnaExp *************************************/

class UnaExp : Expression
{
    Expression e1;

    this(Loc loc, TOK op, Expression e1)
    {
        super(loc, op);
        if (e1) this.source = e1.source;
        this.e1 = e1;
    }

    override Expression semantic(Scope *sc)
    {
        e1 = e1.semantic(sc);
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= Token.toText(op);
        buf ~= ' ';
        e1.toBuffer(buf);
    }
}

/***************************** BinExp *************************************/

class BinExp : Expression
{
    Expression e1;
    Expression e2;

    this(Loc loc, TOK op, Expression e1, Expression e2)
    {
        super(loc, op);
        this.e1 = e1;
        this.e2 = e2;
    }

    override Expression semantic(Scope *sc)
    {
        e1 = e1.semantic(sc);
        e2 = e2.semantic(sc);
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= ' ';
        buf ~= Token.toText(op);
        buf ~= ' ';
        e2.toBuffer(buf);
    }

    void binIR(IRstate *irs, unsigned ret, IRcode ircode)
    {
        uint b;
        uint c;

        if(ret)
        {
            b = irs.alloc(1);
            e1.toIR(irs, b);
            if(e1.match(e2))
            {
                irs.gen3(loc, ircode, ret, b, b);
            }
            else
            {
                c = irs.alloc(1);
                e2.toIR(irs, c);
                irs.gen3(loc, ircode, ret, b, c);
                irs.release(c, 1);
            }
            irs.release(b, 1);
        }
        else
        {
            e1.toIR(irs, 0);
            e2.toIR(irs, 0);
        }
    }
}

/************************************************************/

/* Handle ++e and --e
 */

class PreExp : UnaExp
{
    IRcode ircode;

    this(Loc loc, IRcode ircode, Expression e)
    {
        super(loc, TOK.TOKplusplus, e);
        this.ircode = ircode;
    }

    override Expression semantic(Scope *sc)
    {
        super.semantic(sc);
        e1.checkLvalue(sc);
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= Token.toText(op);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        unsigned base;
        IR property;
        int opoff;

        //writef("PreExp::toIR('%s')\n", toText);
        e1.toLvalue(irs, base, &property, opoff);
        assert(opoff != 3);
        if(opoff == 2)
        {
            //irs.gen2(loc, ircode + 2, ret, property.index);
            irs.gen3(loc, cast(IRcode)(ircode + 2), ret, property.index, property.id.toHash());
        }
        else
            irs.gen3(loc, cast(IRcode)(ircode + opoff), ret, base, property.index);
    }
}

/************************************************************/

class PostIncExp : UnaExp
{
    this(Loc loc, Expression e)
    {
        super(loc, TOK.TOKplusplus, e);
    }

    override Expression semantic(Scope *sc)
    {
        super.semantic(sc);
        e1.checkLvalue(sc);
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= Token.toText(op);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        unsigned base;
        IR property;
        int opoff;

        //writef("PostIncExp::toIR('%s')\n", toText);
        e1.toLvalue(irs, base, &property, opoff);
        assert(opoff != 3);
        if(opoff == 2)
        {
            if(ret)
            {
                irs.gen2(loc, IRcode.IRpostincscope, ret, property.index);
            }
            else
            {
                //irs.gen2(loc, IRpreincscope, ret, property.index);
                irs.gen3(loc, IRcode.IRpreincscope, ret, property.index, property.id.toHash());
            }
        }
        else
            irs.gen3(loc, cast(IRcode)((ret ? IRcode.IRpostinc : IRcode.IRpreinc) + opoff), ret, base, property.index);
    }
}

/****************************************************************/

class PostDecExp : UnaExp
{
    this(Loc loc, Expression e)
    {
        super(loc, TOK.TOKplusplus, e);
    }

    override Expression semantic(Scope *sc)
    {
        super.semantic(sc);
        e1.checkLvalue(sc);
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= Token.toText(op);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        unsigned base;
        IR property;
        int opoff;

        //writef("PostDecExp::toIR('%s')\n", toText);
        e1.toLvalue(irs, base, &property, opoff);
        assert(opoff != 3);
        if(opoff == 2)
        {
            if(ret)
            {
                irs.gen2(loc, IRcode.IRpostdecscope, ret, property.index);
            }
            else
            {
                //irs.gen2(loc, IRpredecscope, ret, property.index);
                irs.gen3(loc, IRcode.IRpredecscope, ret, property.index, property.id.toHash());
            }
        }
        else
            irs.gen3(loc, cast(IRcode)((ret ? IRcode.IRpostdec : IRcode.IRpredec) + opoff), ret, base, property.index);
    }
}

/************************************************************/

class DotExp : UnaExp
{
    Identifier *ident;

    this(Loc loc, Expression e, Identifier * ident)
    {
        super(loc, TOK.TOKdot, e);
        this.ident = ident;
    }

    override void checkLvalue(Scope *sc)
    {
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= '.';
        buf ~= ident.toText;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint base;

        //writef("DotExp::toIR('%s')\n", toText);
        version(all)
        {
            // Some test cases depend on things like:
            //		foo.bar;
            // generating a property get even if the result is thrown away.
            base = irs.alloc(1);
            e1.toIR(irs, base);
            irs.gen3(loc, IRcode.IRgets, ret, base, cast(unsigned)ident);
        }
        else
        {
            if(ret)
            {
                base = irs.alloc(1);
                e1.toIR(irs, base);
                irs.gen3(loc, IRgets, ret, base, cast(unsigned)ident);
            }
            else
                e1.toIR(irs, 0);
        }
    }

    override void toLvalue(IRstate *irs, out unsigned base, IR *property, out int opoff)
    {
        base = irs.alloc(1);
        e1.toIR(irs, base);
        property.id = ident;
        opoff = 1;
    }
}

/************************************************************/

class CallExp : UnaExp
{
    Expression[] arguments;

    this(Loc loc, Expression e, Expression[] arguments)
    {
      //writef("CallExp(e1 = %x)\n", e);
        super(loc, TOK.TOKcall, e);
        this.arguments = arguments;
    }

    override Expression semantic(Scope *sc)
    {
        IdentifierExpression ie;

        //writef("CallExp(e1=%x, %d, vptr=%x)\n", e1, e1.op, *(uint *)e1);
        e1 = e1.semantic(sc);
        //writef("CallExp(e1='%s')\n", e1.toText);

        /*if(e1.op != TOKcall)
            e1.checkLvalue(sc);
*/
        foreach(ref Expression e; arguments)
        {
            e = e.semantic(sc);
        }
        if(arguments.length == 1)
        {
            if(e1.op == TOK.TOKidentifier)
            {
                ie = cast(IdentifierExpression )e1;
                if(ie.ident.toText == "assert")
                {
                    return new AssertExp(loc, arguments[0]);
                }
            }
        }
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= '(';
        for(size_t u = 0; u < arguments.length; u++)
        {
            if(u)
                buf ~= ", "w;
            arguments[u].toBuffer(buf);
        }
        buf ~= ')';
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        // ret = base.property(argc, argv)
        // CALL ret,base,property,argc,argv
        unsigned base;
        unsigned argc;
        unsigned argv;
        IR property;
        int opoff;

        e1.toLvalue(irs, base, &property, opoff);

        if(arguments.length)
        {
            uint u;

            argc = cast(uint)arguments.length;
            argv = irs.alloc(argc);
            for(u = 0; u < argc; u++)
            {
                Expression e;

                e = arguments[u];
                e.toIR(irs, argv + u * INDEX_FACTOR);
            }
            arguments[] = null;         // release to GC
            arguments = null;
        }
        else
        {
            argc = 0;
            argv = 0;
        }
        if(opoff == 3)
            irs.gen4(loc, IRcode.IRcallv, ret, base, argc, argv);
        else if(opoff == 2)
            irs.gen4(loc, IRcode.IRcallscope, ret, property.index, argc, argv);
        else
            irs.gen(loc, cast(IRcode)(IRcode.IRcall + opoff), 5, ret, base, property, argc, argv);

        irs.release(argv, argc);
    }
}

/************************************************************/

class AssertExp : UnaExp
{
    this(Loc loc, Expression e)
    {
        super(loc, TOK.TOKassert, e);
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= "assert("w;
        e1.toBuffer(buf);
        buf ~= ')';
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint linnum;
        uint u;
        unsigned b;

        b = ret ? ret : irs.alloc(1);

        e1.toIR(irs, b);
        u = irs.getIP();
        irs.gen2(loc, IRcode.IRjt, 0, b);
        linnum = cast(uint)loc;
        irs.gen1(loc, IRcode.IRassert, linnum);
        irs.patchJmp(u, irs.getIP());

        if(!ret)
            irs.release(b, 1);
    }
}

/************************* NewExp ***********************************/

class NewExp : UnaExp
{
    Expression[] arguments;

    this(Loc loc, Expression e, Expression[] arguments)
    {
        super(loc, TOK.TOKnew, e);
        this.arguments = arguments;
    }

    override Expression semantic(Scope *sc)
    {
        e1 = e1.semantic(sc);
        for(size_t a = 0; a < arguments.length; a++)
        {
            arguments[a] = arguments[a].semantic(sc);
        }
        return this;
    }

    override void toBuffer(ref wchar[] buf)
    {
        buf ~= Token.toText(op);
        buf ~= ' ';

        e1.toBuffer(buf);
        buf ~= '(';
        for(size_t a = 0; a < arguments.length; a++)
        {
            arguments[a].toBuffer(buf);
        }
        buf ~= ')';
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        // ret = new b(argc, argv)
        // CALL ret,b,argc,argv
        uint b;
        uint argc;
        uint argv;

        //writef("NewExp::toIR('%s')\n", toText);
        b = irs.alloc(1);
        e1.toIR(irs, b);
        if(arguments.length)
        {
            uint u;

            argc = cast(uint)arguments.length;
            argv = irs.alloc(argc);
            for(u = 0; u < argc; u++)
            {
                Expression e;

                e = arguments[u];
                e.toIR(irs, argv + u * INDEX_FACTOR);
            }
        }
        else
        {
            argc = 0;
            argv = 0;
        }

        irs.gen4(loc, IRcode.IRnew, ret, b, argc, argv);
        irs.release(argv, argc);
        irs.release(b, 1);
    }
}

/************************************************************/

class XUnaExp : UnaExp
{
    IRcode ircode;

    this(Loc loc, TOK op, IRcode ircode, Expression e)
    {
        super(loc, op, e);
        this.ircode = ircode;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        e1.toIR(irs, ret);
        if(ret)
            irs.gen1(loc, ircode, ret);
    }
}

class NotExp : XUnaExp
{
    this(Loc loc, Expression e)
    {
        super(loc, TOK.TOKnot, IRcode.IRnot, e);
    }

    override int isBooleanResult()
    {
        return true;
    }
}

class DeleteExp : UnaExp
{
    bool lval;
    this(Loc loc, Expression e)
    {
        super(loc, TOK.TOKdelete, e);
    }

    override Expression semantic(Scope *sc)
    {
        e1.checkLvalue(sc);
        lval = sc.errinfo.message == null;
        //delete don't have to operate on Lvalue, while slightly stupid but perfectly by the standard
        if(!lval)
               sc.errinfo.message = null;
        return this;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        unsigned base;
        IR property;
        int opoff;

        if(lval){
            e1.toLvalue(irs, base, &property, opoff);

            assert(opoff != 3);
            if(opoff == 2)
                irs.gen2(loc, IRcode.IRdelscope, ret, property.index);
            else
                irs.gen3(loc, cast(IRcode)(IRcode.IRdel + opoff), ret, base, property.index);
        }else{
            //e1.toIR(irs,ret);
            irs.gen2(loc,IRcode.IRboolean,ret,true);
        }
    }
}

/************************* CommaExp ***********************************/

class CommaExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKcomma, e1, e2);
    }

    override void checkLvalue(Scope *sc)
    {
        e2.checkLvalue(sc);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        e1.toIR(irs, 0);
        e2.toIR(irs, ret);
    }
}

/************************* ArrayExp ***********************************/

class ArrayExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKarray, e1, e2);
    }

    override Expression semantic(Scope *sc)
    {
        checkLvalue(sc);
        return this;
    }

    override void checkLvalue(Scope *sc)
    {
    }

    override void toBuffer(ref wchar[] buf)
    {
        e1.toBuffer(buf);
        buf ~= '[';
        e2.toBuffer(buf);
        buf ~= ']';
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        unsigned base;
        IR property;
        int opoff;

        if(ret)
        {
            toLvalue(irs, base, &property, opoff);
            assert(opoff != 3);
            if(opoff == 2)
                irs.gen2(loc, IRcode.IRgetscope, ret, property.index);
            else
                irs.gen3(loc, cast(IRcode)(IRcode.IRget + opoff), ret, base, property.index);
        }
        else
        {
            e1.toIR(irs, 0);
            e2.toIR(irs, 0);
        }
    }

    override void toLvalue(IRstate *irs, out unsigned base, IR *property, out int opoff)
    {
        uint index;

        base = irs.alloc(1);
        e1.toIR(irs, base);
        index = irs.alloc(1);
        e2.toIR(irs, index);
        property.index = index;
        opoff = 0;
    }
}

/************************* AssignExp ***********************************/

class AssignExp : BinExp
{
    bool accessor;
    this(Loc loc, Expression e1, Expression e2, bool accessor=false)
    {
        super(loc, TOK.TOKassign, e1, e2);
        this.accessor=accessor;
    }

    override Expression semantic(Scope *sc)
    {
        super.semantic(sc);
        if(e1.op != TOK.TOKcall)            // special case for CallExp lvalue's
            e1.checkLvalue(sc);
        return this;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        unsigned b;

        //writef("AssignExp::toIR('%s')\n", toText);
        if(e1.op == TOK.TOKcall)            // if CallExp
        {
            assert(cast(CallExp)(e1));  // make sure we got it right

            // Special case a function call as an lvalue.
            // This can happen if:
            //	foo() = 3;
            // A Microsoft extension, it means to assign 3 to the default property of
            // the object returned by foo(). It only has meaning for com objects.
            // This functionality should be worked into toLvalue() if it gets used
            // elsewhere.

            unsigned base;
            uint argc;
            uint argv;
            IR property;
            int opoff;
            CallExp ec = cast(CallExp)e1;

            if(ec.arguments.length)
			  argc = cast(uint)ec.arguments.length + 1;
            else
                argc = 1;

            argv = irs.alloc(argc);

            e2.toIR(irs, argv + (argc - 1) * INDEX_FACTOR);

            ec.e1.toLvalue(irs, base, &property, opoff);

            if(ec.arguments.length)
            {
                uint u;

                for(u = 0; u < ec.arguments.length; u++)
                {
                    Expression e;

                    e = ec.arguments[u];
                    e.toIR(irs, argv + (u + 0) * INDEX_FACTOR);
                }
                ec.arguments[] = null;          // release to GC
                ec.arguments = null;
            }

            if(opoff == 3)
                irs.gen4(loc, IRcode.IRputcallv, ret, base, argc, argv);
            else if(opoff == 2)
                irs.gen4(loc, IRcode.IRputcallscope, ret, property.index, argc, argv);
            else
                irs.gen(loc, cast(IRcode)(IRcode.IRputcall + opoff), 5, ret, base, property, argc, argv);
            irs.release(argv, argc);
        }
        else
        {
            unsigned base;
            IR property;
            int opoff;

            b = ret ? ret : irs.alloc(1);
            e2.toIR(irs, b);

            e1.toLvalue(irs, base, &property, opoff);
            assert(opoff != 3);
            if(opoff == 2) {
                if (!accessor) {
                    irs.gen2(loc, IRcode.IRputscope, b, property.index);
                }
            } else {
                irs.gen3(loc, cast(IRcode)(IRcode.IRput + opoff), b, base, property.index);
            }
            if(!ret)
                irs.release(b, 1);
        }
    }
}

/************************* AddAssignExp ***********************************/

class AddAssignExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKplusass, e1, e2);
    }

    override Expression semantic(Scope *sc)
    {
        super.semantic(sc);
        e1.checkLvalue(sc);
        return this;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        /*if(ret == 0 && e2.op == TOKreal &&
           (cast(RealExpression)e2).value == 1)//disabled for better standard conformance
        {
            uint base;
            IR property;
            int opoff;

            //writef("AddAssign to PostInc('%s')\n", toChars());
            e1.toLvalue(irs, base, &property, opoff);
            assert(opoff != 3);
            if(opoff == 2)
                irs.gen2(loc, IRpostincscope, ret, property.index);
            else
                irs.gen3(loc, IRpostinc + opoff, ret, base, property.index);
        }
        else*/
        {
            unsigned r;
            unsigned base;
            IR property;
            int opoff;

            //writef("AddAssignExp::toIR('%s')\n", toText);
            e1.toLvalue(irs, base, &property, opoff);
            assert(opoff != 3);
            r = ret ? ret : irs.alloc(1);
            e2.toIR(irs, r);
            if(opoff == 2)
                irs.gen3(loc, IRcode.IRaddassscope, r, property.index, property.id.toHash());
            else
                irs.gen3(loc, cast(IRcode)(IRcode.IRaddass + opoff), r, base, property.index);
            if(!ret)
                irs.release(r, 1);
        }
    }
}

/************************* BinAssignExp ***********************************/

class BinAssignExp : BinExp
{
    IRcode ircode = IRcode.IRerror;

    this(Loc loc, TOK op, IRcode ircode, Expression e1, Expression e2)
    {
        super(loc, op, e1, e2);
        this.ircode = ircode;
    }

    override Expression semantic(Scope *sc)
    {
        super.semantic(sc);
        e1.checkLvalue(sc);
        return this;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint b;
        uint c;
        unsigned r;
        unsigned base;
        IR property;
        int opoff;

        //writef("BinExp::binAssignIR('%s')\n", toText);
        e1.toLvalue(irs, base, &property, opoff);
        assert(opoff != 3);
        b = irs.alloc(1);
        if(opoff == 2)
            irs.gen2(loc, IRcode.IRgetscope, b, property.index);
        else
            irs.gen3(loc, cast(IRcode)(IRcode.IRget + opoff), b, base, property.index);
        c = irs.alloc(1);
        e2.toIR(irs, c);
        r = ret ? ret : irs.alloc(1);
        irs.gen3(loc, ircode, r, b, c);
        if(opoff == 2)
            irs.gen2(loc, IRcode.IRputscope, r, property.index);
        else
            irs.gen3(loc, cast(IRcode)(IRcode.IRput + opoff), r, base, property.index);
        if(!ret)
            irs.release(r, 1);
    }
}

/************************* AddExp *****************************/

class AddExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKplus, e1, e2);;
    }

    override Expression semantic(Scope *sc)
    {
        return this;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        binIR(irs, ret, IRcode.IRadd);
    }
}

/************************* XBinExp ***********************************/

class XBinExp : BinExp
{
    IRcode ircode = IRcode.IRerror;

    this(Loc loc, TOK op, IRcode ircode, Expression e1, Expression e2)
    {
        super(loc, op, e1, e2);
        this.ircode = ircode;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        binIR(irs, ret, ircode);
    }
}

/************************* OrOrExp ***********************************/

class OrOrExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKoror, e1, e2);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint u;
        unsigned b;

        if(ret)
            b = ret;
        else
            b = irs.alloc(1);

        e1.toIR(irs, b);
        u = irs.getIP();
        irs.gen2(loc, IRcode.IRjt, 0, b);
        e2.toIR(irs, ret);
        irs.patchJmp(u, irs.getIP());

        if(!ret)
            irs.release(b, 1);
    }
}

/************************* AndAndExp ***********************************/

class AndAndExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKandand, e1, e2);
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint u;
        unsigned b;

        if(ret)
            b = ret;
        else
            b = irs.alloc(1);

        e1.toIR(irs, b);
        u = irs.getIP();
        irs.gen2(loc, IRcode.IRjf, 0, b);
        e2.toIR(irs, ret);
        irs.patchJmp(u, irs.getIP());

        if(!ret)
            irs.release(b, 1);
    }
}

/************************* CmpExp ***********************************/



class CmpExp : BinExp
{
    IRcode ircode = IRcode.IRerror;

    this(Loc loc, TOK tok, IRcode ircode, Expression e1, Expression e2)
    {
        super(loc, tok, e1, e2);
        this.ircode = ircode;
    }

    override int isBooleanResult()
    {
        return true;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        binIR(irs, ret, ircode);
    }
}

/*************************** InExp **************************/

class InExp : BinExp
{
    this(Loc loc, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKin, e1, e2);
    }
	override void toIR(IRstate *irs, unsigned ret)
    {
        binIR(irs, ret, IRcode.IRin);
    }
}

/****************************************************************/

class CondExp : BinExp
{
    Expression econd;

    this(Loc loc, Expression econd, Expression e1, Expression e2)
    {
        super(loc, TOK.TOKquestion, e1, e2);
        this.econd = econd;
    }

    override void toIR(IRstate *irs, unsigned ret)
    {
        uint u1;
        uint u2;
        unsigned b;

        if(ret)
            b = ret;
        else
            b = irs.alloc(1);

        econd.toIR(irs, b);
        u1 = irs.getIP();
        irs.gen2(loc, IRcode.IRjf, 0, b);
        e1.toIR(irs, ret);
        u2 = irs.getIP();
        irs.gen1(loc, IRcode.IRjmp, 0);
        irs.patchJmp(u1, irs.getIP());
        e2.toIR(irs, ret);
        irs.patchJmp(u2, irs.getIP());

        if(!ret)
            irs.release(b, 1);
    }
}
