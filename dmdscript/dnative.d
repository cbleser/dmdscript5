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


module dmdscript.dnative;

import dmdscript.script;
import dmdscript.dobject;
import dmdscript.dfunction;
import dmdscript.value;

/******************* DnativeFunction ****************************/

alias Value* function(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist) PCall;

struct NativeFunctionData
{
    d_string string;
    PCall     pcall;
    d_uint32  length;
}

class DnativeFunction : Dfunction
{
    PCall pcall;

    this(PCall func, d_string name, d_uint32 length)
    {
        super(length);
        this.name = name;
        pcall = func;
    }

    this(PCall func, d_string name, d_uint32 length, Dobject o)
    {
        super(length, o);
        this.name = name;
        pcall = func;
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        CallContext.currentcc=cc;
        return (*pcall)(this, cc, othis, ret, arglist);
    }

    /*********************************
     * Initalize table of native functions designed
     * to go in as properties of o.
     */

    static void init(Dobject o, NativeFunctionData[] nfd, ushort attributes)
    {
        Dobject f = Dfunction.getPrototype();
        for(size_t i = 0; i < nfd.length; i++)
        {
            NativeFunctionData* n = &nfd[i];

            o.Put(n.string,
                  new DnativeFunction(n.pcall, n.string, n.length, f),
                  attributes);
        }
    }

    /* Special version of the init
       to initialize Function.prototype to solve boot-strap problem

     */
    static void init_Function(Dobject o, NativeFunctionData[] nfd, ushort attributes)
    {
        Dobject f = o;
        for(size_t i = 0; i < nfd.length; i++)
        {
            NativeFunctionData* n = &nfd[i];

            o.Put(n.string,
                  new DnativeFunction(n.pcall, n.string, n.length, f),
                  attributes);
        }
    }
}
