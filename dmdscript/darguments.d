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


module dmdscript.darguments;

import dmdscript.script;
import dmdscript.dobject;
import dmdscript.identifier;
import dmdscript.value;
import dmdscript.text;
import dmdscript.property;
import dmdscript.errmsgs;

// The purpose of Darguments is to implement "value sharing"
// per ECMA 10.1.8 between the activation object and the
// arguments object.
// We implement it by forwarding the property calls from the
// arguments object to the activation object.

class Darguments : Dobject
{
    //Dobject actobj;             // activation object
    Identifier*[] parameters;
    Value[] arglist;

    override bool isDarguments() const
    {
        return true;
    }

    this(Dobject caller, Dobject callee, Dobject actobj,
        Identifier*[] parameters, Value[] arglist, bool strict_mode)

    {
        super(Dobject.getPrototype());

        //  this.actobj = actobj;
        this.parameters = parameters;
        this.arglist = arglist;

        if (strict_mode) {
            auto thrower=new ThrowTypeError(errmsgtbl[ERR_ARGUMENTS_CALLEE]);
            Value accessor=Value(thrower);
            Value vcaller;
            vcaller.putVSetter(&accessor);
            vcaller.putVGetter(&accessor);
            Put(TEXT_caller, &vcaller, DontConfig|DontEnum, true);
            Put(TEXT_callee, &vcaller, DontConfig|DontEnum, true);
        } else {
            if(caller)
                Put(TEXT_caller, caller, DontEnum, true);
            else
                Put(TEXT_caller, &Value.vnull, DontEnum, true);
            Put(TEXT_callee, callee, DontEnum, true);
        }


        // std.stdio.writefln("arglist.length=%s",arglist.length);
        // std.stdio.writefln("parameters.length=%s",parameters.length);

        // foreach(i,arg;this.arglist) {
        //     std.stdio.writefln("\targ[%s]=%s",i,arg.toInfo);
        // }
        Put(TEXT_length, arglist.length, DontEnum);
        if (parameters.length > arglist.length) {
            this.arglist.length=parameters.length;
        }

        if (!strict_mode) {
            foreach(i,p; parameters) {
                Value paramsetter=Value(new paramSetter(this, cast(d_uint32)i));
                Value paramgetter=Value(new paramGetter(this, cast(d_uint32)i));
                Value param;
                param.putVSetter(&paramsetter);
                param.putVGetter(&paramgetter);
                //Value param;
                //param.putVindirect(&arglist[i]); // Points to the arglist
                // at index
                //*param=arglist[i];
                actobj.Put(p.toText, &param, DontDelete);
                //    std.stdio.writeln("after actobj put");

            }
        } else {
            foreach(i,p; parameters) {
                actobj.Put(p.toText, &(this.arglist[i]), DontDelete);
            }
        }

        //    std.stdio.writeln("After foreach");
/+
        for(uint a = 0; a < arglist.length; a++)
        {
            Put(a, &arglist[a], DontEnum);
        }
+/
    }

    class paramSetter : Dobject {
        Darguments owner;
        d_uint32 index;
        this(Darguments owner, d_uint32 index) {
            super(owner);
            this.owner=cast(Darguments)owner;
            this.index=index;
            assert(this.owner, "owner of lengthGetter must be a Darray");
        }

        override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
        {
            if (arglist.length >=0) {
                owner.arglist[index]=arglist[0];
                *ret=arglist[0];
            } else {
                //-- pass location --> cc.locToErrorInfo(errinfo);
                ret.putVundefined;
                return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_length);
            }
            return null;
        }
    }

    class paramGetter : Dobject {
        Darguments owner;
        d_uint32 index;
        this(Darguments owner, d_uint32 index) {
            super(owner);
            this.owner=cast(Darguments)owner;
            this.index=index;
            assert(owner, "owner of lengthGetter must be a Darray");
        }

        override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
        {
            *ret=owner.arglist[index];
            return null;
        }
    }

    override Value[] keys() {
        Value[] _keys;
        _keys.length=arglist.length;
        foreach(i;0..arglist.length) {
            _keys[i]=i;
        }
        _keys~=super.keys;
        return _keys;
    }

    override Value* get(Value* key, hash_t hash=0) {
        d_uint32 index;
        if (key.isArrayIndex(index) && (index < arglist.length)) {
            if (arglist[index].vtype !is vtype_t.V_REF_ERROR) {
                return &arglist[index];
            }
        }
        return super.get(key, hash);
    }

    override Value* put(Value* key, Value* value, ushort attributes, Setter set, bool define, hash_t hash=0) {
        d_uint32 index;
        if (key.isArrayIndex(index) && (index < arglist.length)) {
            arglist[index]=*value;
            return null;
        } else {
            return super.put(key,value,attributes,set,define,hash);
        }
    }

    override bool HasOwnProperty(const Value* key, bool enumerable) {
        d_uint32 index;
        if (key.isArrayIndex(index) && (index < arglist.length)) {
            if (arglist[index].vtype !is vtype_t.V_REF_ERROR) {
                return true;
            }
        }
        return super.HasOwnProperty(key, enumerable);
    }

    override bool CanPut(d_string PropertyName)
    {
        d_uint32 index;
        return (StringToIndex(PropertyName, index) && index < arglist.length)
               ? true
               : Dobject.CanPut(PropertyName);
    }

    override int HasProperty(d_string PropertyName)
    {
        d_uint32 index;

        return (StringToIndex(PropertyName, index) && index < arglist.length)
               ? 1
               : Dobject.HasProperty(PropertyName);
    }

    override bool Delete(d_string PropertyName)
    {
        d_uint32 index;

        if (StringToIndex(PropertyName, index) && index < arglist.length) {
            const Value ref_error={ _vtype : vtype_t.V_REF_ERROR };
            arglist[index]=ref_error;
            return true;
        } else {
            return Dobject.Delete(PropertyName);
        }
    }
}
