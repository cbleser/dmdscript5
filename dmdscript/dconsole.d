/*
 * Link console in node.js
 * This is just an initial version
 *
 * Upgrading to EcmaScript 5.1 by Carsten Bleser Rasmussen
 */
module dmdscript.dconsole;

import std.stdio;

import dmdscript.value;
import dmdscript.dfunction;
import dmdscript.dobject;
import dmdscript.darray;
import dmdscript.script;
import dmdscript.text;
import dmdscript.threadcontext;
import dmdscript.property;
import dmdscript.dnative;

/* ===================== DConsole_constructor ==================== */

class DConsoleConstructor : Dfunction {
    this() {
        super(0, Dfunction_prototype);
        name = TEXT_Console;

        static enum NativeFunctionData nfd[] =
            [
                { TEXT_log, &Dconsole_log, 1 },
                ];

        DnativeFunction.init(this, nfd, DontEnum);
    }

    override Value* Construct(CallContext *cc, Value *ret, Value[] arglist)
    {
        // ECMA 15.9.3<--- JSON
        Dobject o;
        o = new DConsole();
        ret.putVobject(o);
        return null;
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        return null;
    }
}


/* ===================== JConsole.constructor functions ==================== */

/* ===================== DConsole_prototype ==================== */

class DConsolePrototype : DConsole
{
    this()
    {
        super(Dobject_prototype);

        Dobject f = Dfunction_prototype;

        Put(TEXT_constructor, Dconsole_constructor, DontEnum);

        static enum NativeFunctionData nfd[] =
            [
                //           { TEXT_toString, &Ddate_prototype_toString, 0 },
                ];

        DnativeFunction.init(this, nfd, DontEnum);
        assert(Get("toString"));
    }
}

/* ===================== DConsole.prototype ==================== */



/* ===================== DConsole ==================== */

class DConsole : Dobject
{
    this()
    {
        super(DConsole.getPrototype());
        classname = TEXT_Console;
        //        value.putVnumber(n);
    }

    this(Dobject prototype)
    {
        super(prototype);
        classname = TEXT_Console;
    }

    static void init()
    {
        Dconsole_constructor = new DConsoleConstructor();
        Dconsole_prototype = new DConsolePrototype();

        Dconsole_constructor.Put(TEXT_prototype, Dconsole_prototype,
            DontEnum | DontDelete | ReadOnly);

        assert(Dconsole_prototype.length != 0);
    }

    static Dfunction getConstructor()
    {
        return Dconsole_constructor;
    }

    static Dobject getPrototype()
    {
        return Dconsole_prototype;
    }
}


Value* Dconsole_log(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
    mixin Dobject.SetterT;
    // Our own extension
    if(arglist.length)
    {
        uint i;
        d_string str;
        for(i = 0; i < arglist.length; i++)
        {
            if (arglist[i].isObject) {
                Dobject obj=arglist[i].object;
                str ~= obj.toSource(obj);
            } else {
                str ~= arglist[i].toText;
            }
        }
        writef("%s\n",str);
    }

    ret.putVundefined();
    return null;
}
