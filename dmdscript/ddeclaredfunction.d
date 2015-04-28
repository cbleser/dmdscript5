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

module dmdscript.ddeclaredfunction;

import std.stdio;
import std.c.stdlib;
import std.exception;
import dmdscript.script;
import dmdscript.dobject;
import dmdscript.dfunction;
import dmdscript.darguments;
import dmdscript.opcodes;
import dmdscript.ir;
import dmdscript.identifier;
import dmdscript.value;
import dmdscript.functiondefinition;
import dmdscript.text;
import dmdscript.property;

/* ========================== DdeclaredFunction ================== */

class DdeclaredFunction : Dfunction
{
    FunctionDefinition fd;
    this(FunctionDefinition fd)
    {
        super(cast(uint)fd.parameters.length, Dfunction.getPrototype());
        assert(Dfunction.getPrototype());
        assert(internal_prototype);
        this.fd = fd;
        Dobject o;

        // ECMA 3 13.2
        o = new Dobject(Dobject.getPrototype());        // step 9
        Put(TEXT_prototype, o, DontEnum);         // step 11
        o.Put(TEXT_constructor, this, DontEnum);  // step 10
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        // 1. Create activation object per ECMA 10.1.6
        // 2. Instantiate function variables as properties of
        //    activation object
        // 3. The 'this' value is the activation object

        Dobject actobj;         // activation object
        Darguments args;
        uint i;
        Value* result;

//        writefln("DdeclaredFunction.Call() '%s'", toString());
        //writefln("this.scopex.length = %d", this.scopex.length);
        //writefln("\tinstantiate(this = %x, fd = %x)", cast(void*)this, cast(void*)fd);
        // if it's an empty function, just return
        if(fd.code[0].opcode == IRcode.IRret)
        {
            return null;
        }

        // Generate the activation object
        // ECMA v3 10.1.6
        // if (fd.strict_mode) {
        //     std.stdio.writeln("Function scope is set to undefined object in strict mode");
        //     actobj = new ValueObject(null, &Value.vundefined, TEXT_undefined);
        // } else {
        actobj = new Dobject(null);
        // }
        if(fd.name){
            Value vtmp;//should not be referenced by the end of func

            vtmp.putVobject(this);
            actobj.Put(fd.name, &vtmp, DontDelete);
        }
        // Instantiate the parameters
        version(none)
        {
            uint a = 0;
            foreach(Identifier* p; fd.parameters)
            {
                Value* v = (a < arglist.length) ? &arglist[a++] : &Value.vundefined;
                actobj.Put(p.toText, v, DontDelete);
            }
        }

        // Generate the Arguments Object
        // ECMA v3 10.1.8
        args = new Darguments(cc.caller, this, actobj, fd.parameters, arglist, isStrictMode);

        actobj.Put(TEXT_arguments, args, DontDelete|ReadOnly);
/+
        foreach(i,arg;args) {
            std.stdio.writefln("arg[%s]=%s",i.toInfo,arg.toInfo);
        }
+/
        // The following is not specified by ECMA, but seems to be supported
        // by jscript. The url www.grannymail.com has the following code
        // which looks broken to me but works in jscript:
        //
        //	    function MakeArray() {
        //	      this.length = MakeArray.arguments.length
        //	      for (var i = 0; i < this.length; i++)
        //		  this[i+1] = arguments[i]
        //	    }
        //	    var cardpic = new MakeArray("LL","AP","BA","MB","FH","AW","CW","CV","DZ");
//        Put(TEXT_arguments, args, DontDelete);          // make grannymail bug work




        Dobject[] newScopex;
        newScopex = this.scopex.dup;//copy this function object scope chain
        assert(newScopex.length != 0);
        newScopex ~= actobj; //and put activation object on top of it

        fd.instantiate(newScopex, actobj, DontDelete);

        Dobject[] scopex_save = cc.scopex;
        cc.scopex = newScopex;
//        auto scoperootsave = cc.scoperoot;
//        cc.scoperoot=cast(uint)(newScopex.length-1);
//        cc.scoperoot++;//to accaunt extra activation object on scopex chain
        Dobject variable_save = cc.variable;
        cc.variable = actobj;
        auto caller_save = cc.caller;
        cc.caller = this;
        auto callerf_save = cc.callerf;
        cc.callerf = fd;
        auto strict_mode_save = cc.strict_mode;



        scope(exit) {
            cc.callerf = callerf_save;
            cc.caller = caller_save;
            cc.variable = variable_save;
            cc.scopex = scopex_save;
            cc.strict_mode=strict_mode_save;


//            cc.scoperoot = scoperootsave;
        }
        // locals is only used temporary
        // So we use a stack allocation
        // The new command also clear the locals which means that all
        // locals start out as V_REF_ERROR
        scope Value[] locals=new Value[fd.nlocals];

        cc.strict_mode=fd.strict_mode;
        // std.stdio.writefln("callled Code function othis=%x this=%x",cast(void*)othis,cast(void*)this);
        // if (fd.strict_mode) {
        //     std.stdio.writeln("function code is in strict mode");
        // }
        // if ( othis is this ) {
        //     std.stdio.writefln("Object is the samme as caller and scope strict mode is %s",cc.isStrictMode);
        // }
        if (othis is this ) {
            if ( othis.isStrictMode ) {
                std.stdio.writeln(">>> ISOLATED");
                othis=new ValueObject(null, &Value.vundefined, TEXT_undefined);
            } else {
                othis=cc.global;
            }
        }
        result = IR.call(cc, othis, fd.code, ret, locals.ptr);


        // Remove the arguments object
        //Value* v;
        //v=Get(TEXT_arguments);
        //writef("1v = %x, %s, v.object = %x\n", v, v.getType(), v.object);
        Put(TEXT_arguments, &Value.vundefined, 0);
        //actobj.Put(TEXT_arguments, &vundefined, 0);

        return result;
    }

    override Value* Construct(CallContext *cc, Value *ret, Value[] arglist)
    {
        // ECMA 3 13.2.2
        Dobject othis;
        Dobject proto;
        Value* v;
        Value* result;

        v = Get(TEXT_prototype);
        if(v.isPrimitive())
            proto = Dobject.getPrototype();
        else
            proto = v.toObject();
        othis = new Dobject(proto);
        result = Call(cc, othis, ret, arglist);
        if(!result)
        {
            if(ret.isPrimitive())
                ret.putVobject(othis);
        }
        return result;
    }

    d_string toText()
    {
        wchar[] s;

        //writef("DdeclaredFunction.toString()\n");
        fd.toBuffer(s);
        return assumeUnique(s);
    }

    override bool isStrictMode() {
        return fd.strict_mode;
    }

    override bool isEval() {
        return fd.iseval;
    }

}
