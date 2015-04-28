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

module dmdscript.dobject;

//import std.string;
import std.c.stdarg;
import std.c.string;
import std.exception;
import std.algorithm;

import std.stdio;

import dmdscript.script;
import dmdscript.value;
import dmdscript.dfunction;
import dmdscript.property;
import dmdscript.threadcontext;
import dmdscript.iterator;
import dmdscript.identifier;
import dmdscript.errmsgs;
import dmdscript.text;
import dmdscript.program;

import dmdscript.dboolean;
import dmdscript.dstring;
import dmdscript.dnumber;
import dmdscript.darray;
import dmdscript.dmath;
import dmdscript.ddate;

import dmdscript.djson;
import dmdscript.dconsole;

import dmdscript.dregexp;
import dmdscript.derror;
import dmdscript.dnative;

import dmdscript.protoerror;


//enum int* pfoo = &dmdscript.protoerror.foo;     // link it in

class ErrorValue : Exception {
    Value value;
    this(Value* vptr){
        super("DMDScript exception");
        std.stdio.writefln("%s value = %s", __FUNCTION__, vptr.toText);
        value = *vptr;
    }
}
//debug = LOG;

/************************** Dobject_constructor *************************/

class DobjectConstructor : Dfunction
{
    this()
    {
        super(1, Dfunction_prototype);
        if(Dobject_prototype)
            Put(TEXT_prototype, Dobject_prototype, DontEnum | DontDelete | ReadOnly | DontConfig);
    }

    override Value* Construct(CallContext *cc, Value *ret, Value[] arglist)
    {
        Dobject o;
        Value* v;

        // ECMA 15.2.2
        if(arglist.length == 0)
        {
            o = new Dobject(Dobject.getPrototype());
        }
        else
        {
            v = &arglist[0];
            if(v.isPrimitive())
            {
                if(v.isUndefinedOrNull())
                {
                    o = new Dobject(Dobject.getPrototype());
                }
                else
                    o = v.toObject();
            }
            else
                o = v.toObject();
        }
        //printf("constructed object o=%p, v=%p,'%s'\n", o, v,v.getType());
        ret.putVobject(o);
        return null;
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        Dobject o;
        Value* result;
        // ECMA 15.2.1
        if(arglist.length == 0)
        {
            result = Construct(cc, ret, arglist);
        }
        else
        {
            Value* v;

            v = &arglist[0];
            if(v.isUndefinedOrNull())
                result = Construct(cc, ret, arglist);
            else
            {
                o = v.toObject();
                ret.putVobject(o);
                result = null;
            }
        }
        return result;
    }
}

/* ===================== Dobject_keys ================ */

Value* Dobject_keys(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        return DarrayPrototype.getConstructor.Construct(cc, ret, arglist[0].toObject.keys(DontEnum));
    } else if (arglist.length == 0) {
        //-- pass location --> cc.locToErrorInfo(errinfo);
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_keys);
    }
    ret.putVundefined;
    //-- pass location --> cc.locToErrorInfo(errinfo);
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_getOwnPropertyNames ================ */

Value* Dobject_getOwnPropertyNames(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        return DarrayPrototype.getConstructor.Construct(cc, ret, arglist[0].toObject.keys(0));
    } else if (arglist.length == 0) {
        ErrInfo errinfo;
        //-- pass location --> cc.locToErrorInfo(errinfo);
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_getOwnPropertyNames);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_getOwnPropertyDescriptor ================ */

Value* Dobject_getOwnPropertyDescriptor(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=2 && arglist[0].isObject) {
        Value* result;
        Value[] args;
        result=Dobject.getConstructor.Construct(cc, ret, args);
        if (result) return result;
        auto prop=arglist[0].toObject._proptable.getProperty(arglist[1].toText);
        if (!prop) {
            ret.putVundefined;
            return null;
        }

        Value attr;
        ret.putVobject(new Dobject(Dobject.getPrototype));
        if (prop.value.isAccessor) {
            if (prop.value.setter) {
                ret.object.Put(TEXT_set,  prop.value.setter, DontDelete, true);
            }
            if (prop.value.getter) {
                ret.object.Put(TEXT_get,  prop.value.getter, DontDelete, true);
            }
        } else {
            attr=((prop.attributes & ReadOnly)==0);
            ret.object.Put(TEXT_writable,    &attr, DontDelete);
            ret.object.Put(TEXT_value, &prop.value, DontDelete);
        }
        attr=((prop.attributes & DontEnum)==0);
        ret.object.Put(TEXT_enumerable,   &attr, DontDelete);
        attr=((prop.attributes & DontConfig)==0);
        ret.object.Put(TEXT_configurable, &attr, DontDelete);
        return null;
    } else if (arglist.length <= 1) {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_getOwnPropertyDescriptor);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_defineDescriptor ================ */

private Value* Dobject_defineProperty(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    mixin Dobject.SetterT;
    if (arglist.length >=3 && arglist[0].isObject && arglist[2].isObject) {
        Value value;
        bool writable;
        bool enumerable;
        bool configurable;
        ushort attributes;
        //ushort umask;
        auto obj=arglist[0].toObject;
        auto propname=arglist[1].toText;
        Property* prop=obj._proptable.getProperty(propname);
        attributes=(DontEnum|DontConfig|ReadOnly);
        if (prop) {
            if ((prop.attributes & DontConfig)!=0)  {
                return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_IMMUTABLE], propname);
            }
            writable=(prop.attributes & ReadOnly)==0;
            enumerable=(prop.attributes & DontEnum)==0;
            configurable=(prop.attributes & DontConfig)==0;
            attributes=prop.attributes;
            value.copyTo(&prop.value);
        }


        auto desc_obj=arglist[2].toObject;
        Value* desc_value=desc_obj.Get(TEXT_value);
        Value* desc_set=desc_obj.Get(TEXT_set);
        Value* desc_get=desc_obj.Get(TEXT_get);

        if (desc_value) {
            if (desc_set || desc_get) {
                ret.putVundefined;
                return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_VALUE_SETGET], propname);
            }
            value.copyTo(desc_value);
        } else { // Initial setter and getters
            if (desc_set || desc_get) {
                value.putVSetter(desc_set);
                value.putVGetter(desc_get);
            } else {
                value.putVundefined;
            }
            // attributes|=(DontEnum|ReadOnly);
        }

        Value* desc=desc_obj.Get(TEXT_writable);
        if (desc) {
            //umask|=ReadOnly;
            writable=desc.toBoolean; // Writeable default true
            attributes&=~ReadOnly;
            attributes|=(desc.toBoolean)?0:ReadOnly;
        }

        desc=desc_obj.Get(TEXT_enumerable);
        if (desc) {
            //umask|=DontEnum;
            enumerable=desc.toBoolean; // Enumerable default true
            attributes&=~DontEnum;
            attributes|=(desc.toBoolean)?0:DontEnum;

        }
        desc=desc_obj.Get(TEXT_configurable);
        if (desc) {
            //umask|=DontConfig;
            configurable=desc.toBoolean; // Enumerable default true
            attributes&=~DontConfig;
            attributes|=(desc.toBoolean)?0:DontConfig;

        }

        obj.Put(propname, &value, attributes, true);
        return null;
    } else if (arglist.length < 3) {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_defineProperty);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}


/* ===================== Dobject_defineProperties ================ */

private Value* Dobject_defineProperties(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=2 && arglist[0].isObject && arglist[1].isObject) {
        Dobject obj=arglist[0].toObject;
        Dobject props=arglist[1].toObject;
        Value* result;
        foreach(key ; props.keys(0)) {
            Value* arg=props.Get(key.toText);
            result=Dobject_defineProperty(othis, cc, obj, ret, arg[0..1]);
            if (result)
                return result;
        }
        ret.putVundefined;
        return result;
    } else if (arglist.length < 2) {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_defineProperties);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_create ================ */

private Value* Dobject_create(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{

    if (arglist.length >=1 && arglist[0].isObject) {
        Value* result;
        Dobject proto=arglist[0].toObject;
        Dobject obj=new Dobject(proto);
        if ( (arglist.length >=2) && arglist[1].isObject) {
            Dobject props=arglist[1].toObject;
            foreach(key ; props.keys(0)) {
                Value* arg=props.Get(key.toText);
                result=Dobject_defineProperty(othis, cc, obj, ret, arg[0..1]);
                if (result)
                    return result;
            }
        }
        ret.putVobject(obj);
        return result;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_create);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_preventExtension ================ */

private Value* Dobject_preventExtensions(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        Dobject o =arglist[0].toObject;
        o.prevent_extensions=true;
        ret=&arglist[0];
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_preventExtensions);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_seal ================ */

private Value* Dobject_seal(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        Dobject o =arglist[0].toObject;
        o.sealed=true;
        ret=&arglist[0];
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_seal);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_freeze ================ */

private Value* Dobject_freeze(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        Dobject o =arglist[0].toObject;
        o.frozen=true;
        ret=&arglist[0];
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_freeze);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_isExtensible ================ */

private Value* Dobject_isExtensible(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        Dobject o =arglist[0].toObject;
        ret.putVboolean(o.isExtensible);
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_isExtensible);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_isSealed ================ */

private Value* Dobject_isSealed(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        Dobject o =arglist[0].toObject;
        ret.putVboolean(o.isSealed);
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_isSealed);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}

/* ===================== Dobject_isFrozen ================ */

private Value* Dobject_isFrozen(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    if (arglist.length >=1 && arglist[0].isObject) {
        Dobject o =arglist[0].toObject;
        ret.putVboolean(o.isFrozen);
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_DISP_E_BADPARAMCOUNT], TEXT_isFrozen);
    }
    ret.putVundefined;
    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_INVALID_OBJECT], arglist[0]);
}


/* ===================== Dobject_prototype_toString ================ */

Value* Dobject_prototype_toString(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    d_string s;
    d_string string;

    //debug (LOG) writef("Dobject.prototype.toString(ret = %x)\n", ret);

    s = othis.classname;
    string = format("[object %s]", s);
    ret.putVstring(string);
    return null;
}


/* ===================== Dobject_prototype_toLocaleString ================ */

Value* Dobject_prototype_toLocaleString(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.2.4.3
    //	"This function returns the result of calling toString()."

    Value* v;

    //writef("Dobject.prototype.toLocaleString(ret = %x)\n", ret);
    v = othis.Get(TEXT_toString);
    writeln("toLocalString ",v.toText,":", othis," ",pthis);
    writeln("arglist.length ",arglist.length);

    if(v && !v.isPrimitive())   // if it's an Object
    {
        Value* a;
        Dobject o;

        o = v.object;
        a = o.Call(cc, othis, ret, arglist);
        if(a)                   // if exception was thrown
            return a;
    }
    return null;
}

/* ===================== Dobject_prototype_valueOf ================ */

Value* Dobject_prototype_valueOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    ret.putVobject(othis);
    return null;
}

/* ===================== Dobject_prototype_toSource ================ */

Value* Dobject_prototype_toSource(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    ret.putVstring(othis.toSource(othis));
    return null;
}

/* ===================== Dobject_prototype_hasOwnProperty ================ */

Value* Dobject_prototype_hasOwnProperty(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.2.4.5
    Value* v;

    v = arglist.length ? &arglist[0] : &Value.vundefined;
    v.toHash;
    ret.putVboolean(othis.HasOwnProperty(v, 0));
    return null;
}

/* ===================== Dobject_prototype_isPrototypeOf ================ */

Value* Dobject_prototype_isPrototypeOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.2.4.6
    d_boolean result = false;
    Value* v;
    Dobject o;

    v = arglist.length ? &arglist[0] : &Value.vundefined;
    if(!v.isPrimitive())
    {
        o = v.toObject();
        for(;; )
        {
            o = o.internal_prototype;
            if(!o)
                break;
            if(o == othis)
            {
                result = true;
                break;
            }
        }
    }

    ret.putVboolean(result);
    return null;
}

/* ===================== Dobject_prototype_propertyIsEnumerable ================ */

Value* Dobject_prototype_propertyIsEnumerable(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v3 15.2.4.7
    Value* v;

    v = arglist.length ? &arglist[0] : &Value.vundefined;
    v.toHash;
    ret.putVboolean(othis._proptable.hasownproperty(v, 1));
    return null;
}

/* ===================== Dobject_prototype_getPrototypeOf ================ */

Value* Dobject_prototype_getPrototypeOf(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    // ECMA v5 15.2.3.2
    Dobject result;
    Value* v;
    Value* exception;
    Dobject o;

    v = arglist.length ? &arglist[0] : &Value.vundefined;
    if(!v.isPrimitive())
    {
        o = v.toObject();
        for(;; )
        {
            o = o.internal_prototype;
            if(!o)
                break;
            if(o != othis)
            {
                result = o;
                break;
            }
        }
    }

    if (result) {
        ret.putVobject(result);
        return null;
    } else {
        ret.putVundefined;
        return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_OBJECT_EXPECTED], v.getType);
    }
}

/* ===================== Dobject_prototype ========================= */

class DobjectPrototype : Dobject {
    this()
    {
        super(null);
    }
}


/* ====================== Dobject ======================= */

class Dobject
{

    mixin template SetterT() {
        Setter setter(Dobject o) {
            Value* local_setter(Value* caller, Value* ret, Value* arg) {
                if (caller.isAccessor) {
                    static if (!is(typeof(cc))) {
                        CallContext* cc=CallContext.currentcc;
                    }
                    return caller.callSet(cc, o, ret, arg[0..1]);
                }
                if (ret !is arg) {
                    arg.copyTo(ret);
                }
                return null;
            }
            return &local_setter;
        }
    }

    Value* getter(Value* val) {
        if (val && val.isAccessor) {
            Value* ret=new Value;
            Value* err=val.callGet(CallContext.currentcc, this, ret);
            if (err) {
                return err;
            }
            return ret;
        }
        return val;
    }
    private PropTable* _proptable;
    Dobject internal_prototype;
    d_string classname;
    Value value;
// Set the limit to some iteration loop to prevent it from being to large
    static uint iteration_limit;


    enum uint DOBJECT_SIGNATURE = 0xAA31EE31;
    uint signature;
    protected bool prevent_extensions;
    protected bool sealed;
    protected bool frozen;
    bool isolated; // Swicth used to isolate eval functions

    static private int recursion_id_count;
    private int recursion_id;


    this(Dobject prototype)
    {
        //writef("new Dobject = %x, prototype = %x, line = %d, file = '%s'\n", this, prototype, GC.line, ascii2unicode(GC.file));
        //writef("Dobject(prototype = %p)\n", prototype);
        _proptable = new PropTable(this);
        internal_prototype = prototype;
/* this is now done in PropTable
        if(prototype)
            proptable.previous = prototype.proptable;
*/
        classname = TEXT_Object;
        value.putVobject(this);

        signature = DOBJECT_SIGNATURE;
    }

    /* used ny scope cloning */
    Dobject clone() {
        Dobject o=new Dobject(internal_prototype);
        foreach(ref key, ref prop; this) {
            o.put(&key, &prop.value, prop.attributes, null, true);
        }
        return o;
    }

    static int newRecursion() {
        recursion_id_count++;
        return recursion_id_count;
    }

    void setRecursion(int recursion_id) {
        this.recursion_id=recursion_id;
    }

    /**
       check it the object was in the recursion
     */
    bool wasInRecursion(int recursion_id) const {
        // If recursion_id is greate than or equal to the current
        // recursion then the object has already been visited
        return (this.recursion_id-recursion_id)>=0;
    }

    bool isExtensible() const {
        return !prevent_extensions;
    }

    bool isSealed() const {
        return sealed;
    }

    bool isFrozen() const {
        return frozen;
    }

    Dobject Prototype()
    {
        return internal_prototype;
    }

    @property
    PropTable* proptable() {
        return _proptable;
    }

    Value* Get(Value* key) {
        return getter(get(key));
    }

    Value* Get(d_string PropertyName)
    {
        Value vname=Value(PropertyName);
        return getter(get(&vname));
    }

    Value* Get(Identifier* id)
    {
        return getter(get(id.toValue));
    }

    Value* Get(d_string PropertyName, hash_t hash)
    {
        scope Value key=Value(PropertyName);
        return getter(get(&key, hash));
    }

    Value* Get(d_uint32 index)
    {
        Value* v;
        Value vindex=Value(index);
        return getter(get(&vindex));
    }

    Value* Get(d_uint32 index, Value* vindex)
    in {
        assert(vindex.toUint32 == index);
    }
    out {
        assert(vindex.toHash == Value.calcHash(index));
    }
    body
    {
        scope Value key=Value(index);
        return getter(get(&key, vindex.toHash));
    }


    Value* opIndexAssign(T)(T x, d_string propertyName) {
        static if (is(T==Value)) {
            return Put(propertyName, &x, 0);
        } else static if (is(T==Value*)) {
            return Put(propertyName, x, 0);
        } else {
            Value val;
            val=x;
            return Put(propertyName, &val, 0);
        }
    }

    Value* opIndexAssign(T)(T x, d_uint32 index) {
        static if (is(T==Value)) {
            return Put(index, &x, 0);
        } else static if (is(T==Value*)) {
            return Put(index, x, 0);
        } else {
            Value val;
            val=x;
            return Put(index, &val, 0);
        }
    }

    Value* opIndex(d_string propertyName) {
        return Get(propertyName);
    }

    Value* opIndex(d_uint32 index) {
        return Get(index);
    }

    bool canput(const Value* key, hash_t hash, out Property* ownprop)
    in {
        assert(key.hasHash);
    } body {
        return _proptable.canput(key,hash,ownprop);
    }

    Value* put(Value* key, Value* value, ushort attributes, Setter set, bool define, hash_t hash=0)
    in {
        if (hash) assert(hash==key.toHash);
    } body {
        if (key.isObject) {
            scope Value vname;
            Value* result=key.toPrimitive(&vname, TEXT_valueOf);
            if (result) return result;

            return _proptable.put(&vname, vname.toHash, value, attributes, set, define);
        } else if (key.isAccessor) {
            assert(0, "dobject.put for accessor not implemented yet");
        } else {
            return _proptable.put(key, (hash)?hash:key.toHash, value, attributes, set, define);
        }
        return null;
    }

    bool del(Value* key) {
        if (key.isObject) {
            scope Value vname;
            Value* result=key.toPrimitive(&vname, TEXT_valueOf);
            if (result) return false;
            return _proptable.del(&vname, vname.toHash);
        } else if (key.isAccessor) {
            assert(0, "dobject.del for accessor not implemented yet");
        } else {
            return _proptable.del(key, key.toHash);
        }
        return false;
    }

    Value* get(Value* key, hash_t hash=0) {
        if (key.isObject) {
            scope Value vname;
            Value* result=key.toPrimitive(&vname, TEXT_valueOf);
            if (result) return result;
            return getter(_proptable.get(&vname, (hash)?hash:vname.toHash));
        } else if (key.isAccessor) {
            assert(0, "dobject.get for accessor not implemented yet");
        } else {
            return getter(_proptable.get(key, (hash)?hash:key.toHash));
        }
        return null;
    }

    @property uint length() const {
        return cast(uint)_proptable.length;
    }

    Value[] keys() {
        return _proptable.keys;
    }

    Property* opIn_r(Value key)
    {
        key.toHash;
        return _proptable.opIn_r(key);
    }

    bool del(d_string name) {
        scope Value vname=Value(name);
        return del(&vname);
    }

    bool del(d_uint32 index) {
        scope Value vname=Value(index);
        return del(&vname);
    }

    Value* Put(d_string PropertyName, Value* value, ushort attributes, bool define=false, ushort umask=0)
    {
        mixin Dobject.SetterT;
        // ECMA 8.6.2.2
        scope Value vname=Value(PropertyName);
        return put(&vname, value, attributes, setter(this), define);
    }


    Value* Put(Identifier* key, Value* value, ushort attributes, bool define=false)
    {
        mixin Dobject.SetterT;
        // ECMA 8.6.2.2
        // writef("Dobject.Put(this = %p)\n", this);
        return put(key.toValue, value, attributes, setter(this), define);
    }

    Value* Put(d_string PropertyName, Dobject o, ushort attributes, bool define=false)
    {
        mixin Dobject.SetterT;
        // ECMA 8.6.2.2
        scope Value v;
        v.putVobject(o);
        scope Value vname=Value(PropertyName);
        return put(&vname, &v, attributes, setter(this), define);
    }

    Value* Put(d_string PropertyName, d_number n, ushort attributes, bool define=false)
    {
        mixin Dobject.SetterT;
        // ECMA 8.6.2.2
        scope Value v=Value(n);
        scope Value vname=Value(PropertyName);
        return put(&vname, &v, attributes, setter(this), define);
    }

    Value* Put(d_string PropertyName, d_string s, ushort attributes, bool define=false)
    {
        mixin Dobject.SetterT;
        // ECMA 8.6.2.2
        scope Value v=Value(s);
        scope Value vname=Value(PropertyName);
        return put(&vname, &v, attributes, setter(this), define);
    }


    Value* Put(d_uint32 index, Value* vindex, Value* value, ushort attributes, bool define=false)
    in {
        assert(vindex.toUint32 == index);
    }
    body
    {
        // ECMA 8.6.2.2
        return put(vindex, value, attributes, null, define, vindex.toHash);
    }


    Value* Put(d_uint32 index, Value* value, ushort attributes, bool define=false)
    {
        // ECMA 8.6.2.2
        scope Value vindex=Value(index);
        return put(&vindex, value, attributes, null, define);
    }

    Value* PutDefault(Value* value) {
        // Not ECMA, Microsoft extension
        return RuntimeError(CallContext.currentcc.errorInfo, ERR_NO_DEFAULT_PUT);
    }

    Value* put_Value(Value* ret, Value[] arglist) {
        // Not ECMA, Microsoft extension
        return RuntimeError(CallContext.currentcc.errorInfo, ERR_FUNCTION_NOT_LVALUE);
    }

    bool CanPut(d_string PropertyName)
    {
        // ECMA 8.6.2.3
        Value v;
        v.putVstring(PropertyName);
        Property* own;
        return canput(&v, v.toHash(), own);
    }

    int HasProperty(d_string PropertyName)
    {
        // ECMA 8.6.2.4
        return _proptable.hasproperty(PropertyName);
    }

    bool HasOwnProperty(const Identifier* id, bool enumerable) {
        return HasOwnProperty(id.toValue, enumerable);
    }

    bool HasOwnProperty(const Value* key, bool enumerable)
       in {
        assert(key.hasHash);
    } body {
        return _proptable.hasownproperty(key, enumerable);
    }

    /***********************************
     * Return:
     *	TRUE	not found or successful delete
     *	FALSE	property is marked with DontDelete attribute
     */

    bool Delete(d_string PropertyName) {
        // ECMA 8.6.2.5
        scope Value vname=Value(PropertyName);
        return _proptable.del(&vname, vname.toHash);
    }

    bool Delete(d_uint32 index)
    {
        // ECMA 8.6.2.5
        scope Value vindex=Value(index);
        return _proptable.del(&vindex, vindex.toHash);
    }

    bool implementsDelete() const    {
        // ECMA 8.6.2 says every object implements [[Delete]],
        // but ECMA 11.4.1 says that some objects may not.
        // Assume the former is correct.
        return true;
    }

    Value* DefaultValue(Value* ret, d_string Hint) {
        Dobject o;
        Value* v;
        static enum d_string[2] table = [ TEXT_toString, TEXT_valueOf ];
        int i = 0;                      // initializer necessary for /W4

        // ECMA 8.6.2.6
        //writef("Dobject.DefaultValue(ret = %x, Hint = '%s')\n", cast(uint)ret, Hint);

        if(Hint == TypeString ||
           (Hint == null && this.isDdate()))
        {
            i = 0;
        }
        else if(Hint == TypeNumber ||
                Hint == null)
        {
            i = 1;
        }
        else
            assert(0);


        for(int j = 0; j < 2; j++)
        {
            d_string htab = table[i];

            //writefln("\ti = %d, htab = '%s'", i, htab);
            v = Get(htab);
            //writefln("\tv = %x", cast(uint)v);
            if(v && !v.isPrimitive())   // if it's an Object
            {
                Value* a;
                CallContext *cc;

                //writefln("\tfound default value");
                o = v.object;
                //  cc = Program.getProgram().callcontext;
                cc = CallContext.currentcc;
                a = o.Call(cc, this, ret, null);
                if(a)                   // if exception was thrown
                    return a;
                if(ret.isPrimitive())
                    return null;
            }
            i ^= 1;
        }
        return Dobject.RuntimeError(CallContext.currentcc.errorInfo, "No [[DefaultValue]]");
        //ErrInfo errinfo;
        //return RuntimeError(&errinfo, DTEXT("no Default Value for object"));
    }

    Value* Construct(CallContext *cc, Value *ret, Value[] arglist) {
        return RuntimeError(cc.errorInfo, errmsgtbl[ERR_S_NO_CONSTRUCT], classname);
    }

    Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist) {
        return RuntimeError(cc.errorInfo, errmsgtbl[ERR_S_NO_CALL], classname);
    }

    void *HasInstance(Value* ret, Value* v) {
        // ECMA v3 8.6.2
        return RuntimeError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_S_NO_INSTANCE], classname);
    }

    d_string getTypeof() const
    {   // ECMA 11.4.3
        return TEXT_object;
    }


    bool isClass(d_string classname) const
    {
        return this.classname == classname;
    }

    bool isDarray() const
    {
        return isClass(TEXT_Array);
    }
    bool isDdate() const
    {
        return isClass(TEXT_Date);
    }
    bool isDregexp() const
    {
        return isClass(TEXT_RegExp);
    }

    bool isDarguments() const
    {
        return false;
    }
    bool isCatch() const
    {
        return false;
    }
    bool isFinally() const
    {
        return false;
    }

    void getErrInfo(out ErrInfo errinfo) {
        Value v;
        v.putVobject(this);

        errinfo.message = v.toText;
    }

    Value[] keys(ushort attributes) {
        Value[] result;
        foreach(k, p ; *_proptable) {
            Value value;
            if ( (p.attributes & attributes)==0 ) {
                value.copyTo(&k);
                result~=value;
            }
        }
        return result;
    }


    uint[] indices(ushort attributes, const uint fromIndex=0, const uint toIndex=uint.max) {
        uint[] result;
        foreach(k, p; *_proptable) {
            uint index;
            if ( ((p.attributes & attributes)==0) && (k.isUint32(index)) ) {
                if ( (index>=fromIndex) && (index<toIndex) ) {
                    result~=index;
                }
            }
        }
        return result;
    }

    d_string toSource(Dobject root) {
        d_string buf;
        bool any=false;
        buf = "{";
        foreach(Value key, Property p; *_proptable)
        {
            if(!(p.attributes & (DontEnum | Deleted)))
            {
                if(any)
                    buf ~= ",\n";
                any = true;
                buf ~= key.toText;
                buf ~= " : ";
                buf ~= p.value.toSource(root);
            }
        }

        buf ~= "}";
        return buf;
    }

    IndexIterator getIndexIterator(ushort attributes, bool revert=false, const uint fromIndex=0, const uint toIndex=uint.max) {
        enum small_loop_len=50;
        IndexIterator iter;
        iter.owner=this;
        iter.indices=indices(attributes, fromIndex, (toIndex==0)?toIndex.max:toIndex);
        if (revert) {
            sort!((a,b) { return a>b;})(iter.indices);
        } else {
            sort!((a,b) { return a<b;})(iter.indices);
        }
        return  iter;
    }

    int opApply(int delegate(ref Property) dg) {
        if (_proptable.table is null) return 0;
        int result;
        foreach(ref Property p; _proptable.table)
        {
            result = dg(p);
            if(result)
                break;
        }
        return result;
    }

    int opApply(int delegate(ref Value key, ref Property prop) dg)
    {
        if (_proptable.table is null) return 0;
        int result;

        foreach(Value key, ref Property p; _proptable.table)
        {
            result = dg(key, p);
            if(result)
                break;
        }
        return result;
    }


    struct IndexIterator {
        private Dobject owner;
        private uint[] indices;
        int opApply(scope int delegate(uint) dg) {
            foreach(i; indices) {
                int result=dg(i);
                if (result) return result;
            }
            return 0;
        }

    }

    unittest {
        Dobject o=new Dobject(Dobject.getPrototype());
        auto iter=o.getIndexIterator(0, false);
        uint j;
        // Emptry loop
        foreach(i; iter) {
            assert(0, "Should be an empty array");
        }
        // Ono element
        o[3]="a";
        iter=o.getIndexIterator(0, false);
        j=0;
        foreach(i; iter) {
            j++;
        }

        assert(j==1);
        // Forward loop with index array
        o[1]=10;
        o[2]=39;
        iter=o.getIndexIterator(0, false);
        j=0;
        foreach(i ; iter) {
            j++;
            assert(j==i);
        }
        // Reverse loop with index array
        iter=o.getIndexIterator(0, true);
        j=3;
        foreach(i ; iter) {
            assert(j==i);
            j--;
        }
        // Sparse loop test
        o[TEXT_length]=10;
        o[10]=13;
        o[123456]=13;
        j=0;
        uint prev_i=0;
        iter=o.getIndexIterator(0, false);
        foreach(i ; iter) {
            assert(prev_i<i);
            j++;
            prev_i=i;
        }
        assert(j==5);
        // Sparse loop test reverse
        j=0;
        prev_i=prev_i.max;
        iter=o.getIndexIterator(0, true);
        foreach(i ; iter) {
            assert(prev_i>i);
            j++;
            prev_i=i;
        }
        assert(j==5);
        // Range limit forward
        prev_i=0;
        j=0;
        iter=o.getIndexIterator(0, false, 2, 10);
        foreach(i ; iter) {
            assert(prev_i<i);
            j++;
            prev_i=i;
        }
        assert(j==2);
        // Range limit reverse
        prev_i=prev_i.max;
        j=0;
        iter=o.getIndexIterator(0, true, 2, 10);
        foreach(i ; iter) {
            assert(prev_i>i);
            j++;
            prev_i=i;
        }
        assert(j==2);

    }

    static Value* RuntimeError(ErrInfo errinfo, int msgnum) {
        return RuntimeError(errinfo, errmsgtbl[msgnum]);
    }

    static Value* RuntimeError(ErrInfo errinfo, ...) {
        Dobject o;
        wchar[] buffer;

        std.format.doFormat((dchar c) {buffer~=cast(wchar)c;}, _arguments, _argptr);
        errinfo.message = buffer.idup;
        o = new typeerror.D0(errinfo);
        Value* v = new Value;
        v.putVobject(o);
        return v;
    }

    static Value* ReferenceError(ErrInfo errinfo, int msgnum)
    {
        return ReferenceError(errinfo, errmsgtbl[msgnum]);
    }

    static Value* ReferenceError(ErrInfo errinfo, ...)
    {
        Dobject o;
        errinfo.message = sformat(null,_arguments, _argptr);

        o = new referenceerror.D0(errinfo);
        Value* v = new Value;
        v.putVobject(o);
        return v;
    }

    static Value* RangeError(ErrInfo errinfo, int msgnum)
    {
        return RangeError(errinfo, errmsgtbl[msgnum]);
    }

    static Value* RangeError(ErrInfo errinfo, ...)
    {
        Dobject o;

        errinfo.message = sformat(null, _arguments, _argptr);

        o = new rangeerror.D0(errinfo);
        Value* v = new Value;
        v.putVobject(o);
        return v;
    }


    static Value* SyntaxError(ErrInfo perrinfo, ...)
    {
        Dobject o;

        perrinfo.message = sformat(null, _arguments, _argptr);

        o = new syntaxerror.D0(perrinfo);
        Value* v = new Value;
        v.putVobject(o);
        return v;
    }

    static Value* TypeError(ErrInfo errinfo, ...) {
        Dobject o;

        errinfo.message = sformat(null, _arguments, _argptr);

        o = new typeerror.D0(errinfo);
        Value* v = new Value;
        v.putVobject(o);
        return v;
    }


    Value* putIterator(Value* v)
    {
        Iterator* i = new Iterator;
        i.ctor(this);
        v.putViterator(i);
        return null;
    }

    static Dfunction getConstructor()
    {
        return Dobject_constructor;
    }

    static Dobject getPrototype()
    {
        return Dobject_prototype;
    }

    static void init()
    {
        Dobject_prototype = new DobjectPrototype();
        Dfunction.init();
        Dobject_constructor = new DobjectConstructor();

        static enum NativeFunctionData nfd_cntr[] =
        [
           { TEXT_keys, &Dobject_keys, 1 },
           { TEXT_getOwnPropertyNames, &Dobject_getOwnPropertyNames, 1},
           { TEXT_getOwnPropertyDescriptor, &Dobject_getOwnPropertyDescriptor, 2},
           { TEXT_create, &Dobject_create, 2},
           { TEXT_defineProperty, &Dobject_defineProperty, 3},
           { TEXT_defineProperties, &Dobject_defineProperties, 2},
           { TEXT_preventExtensions, &Dobject_preventExtensions, 1},
           { TEXT_seal, &Dobject_seal, 1},
           { TEXT_freeze, &Dobject_freeze, 1},
           { TEXT_isExtensible, &Dobject_isExtensible, 1},
           { TEXT_isSealed, &Dobject_isSealed, 1},
           { TEXT_isFrozen, &Dobject_isFrozen, 1}

        ];

        DnativeFunction.init(Dobject_constructor, nfd_cntr, DontEnum);


        Dobject op = Dobject_prototype;

        op.Put(TEXT_constructor, Dobject_constructor, DontEnum);

        static enum NativeFunctionData nfd[] =
        [
            { TEXT_toString, &Dobject_prototype_toString, 0 },
            { TEXT_toLocaleString, &Dobject_prototype_toLocaleString, 0 },
            { TEXT_toSource, &Dobject_prototype_toSource, 0 },
            { TEXT_valueOf, &Dobject_prototype_valueOf, 0 },
            { TEXT_hasOwnProperty, &Dobject_prototype_hasOwnProperty, 1 },
            { TEXT_isPrototypeOf, &Dobject_prototype_isPrototypeOf, 0 },
            { TEXT_propertyIsEnumerable, &Dobject_prototype_propertyIsEnumerable, 0 },
            { TEXT_getPrototypeOf, &Dobject_prototype_getPrototypeOf, 1 },
        ];

        DnativeFunction.init(op, nfd, DontEnum);

     }

    // Return the number of properties in this object
    @property uint length() {
        return _proptable.length;
    }

    @property bool isStrictMode() {
        return false;
    }

    @property bool isEval() {
        return false;
    }

    // Return the number of properties in this object prototypes included
    uint lengthAll() {
        size_t result;
        for (Dobject obj=this; obj !is obj.getPrototype ; obj=obj.getPrototype) result+=obj.length;
        return cast(uint)result;
    }
}

class ValueObject : Dobject {
    this(Dobject prototype, Value* value, d_string classname) {
        super(prototype);
        this.classname=classname;
        this.value=*value;
    }

    override d_string getTypeof() const {
        return classname;
    }
}

class ThrowTypeError : Dobject {
    ErrInfo* perrinfo;
    d_string msg;
    this(d_string msg) {
        this.msg=msg;
        super(Dfunction.getPrototype);
        //  assert(perrinfo, "thower of ThrowTypeError must be defined");
    }

    override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        *ret=Dobject.TypeError(cc.errorInfo, errmsgtbl[ERR_ARGUMENTS_CALLEE]);
        return ret;
    }
}

/*********************************************
 * Initialize the built-in's.
 */

void dobject_init()
{
    //writef("dobject_init(tc = %x)\n", cast(uint)tc);
    if(Dobject_prototype)
        return;                 // already initialized for this thread

    version(none)
    {
        writef("sizeof(Dobject) = %d\n", sizeof(Dobject));
        writef("sizeof(PropTable) = %d\n", sizeof(PropTable));
        writef("offsetof(proptable) = %d\n", offsetof(Dobject, _proptable));
        writef("offsetof(internal_prototype) = %d\n", offsetof(Dobject, internal_prototype));
        writef("offsetof(classname) = %d\n", offsetof(Dobject, classname));
        writef("offsetof(value) = %d\n", offsetof(Dobject, value));
    }
    Dobject.init();
    Dboolean.init();
    Dstring.init();
    Dnumber.init();
    Darray.init();
    Dmath.init();
    Ddate.init();
    DJSON.init();
    Dregexp.init();
    Derror.init();
    DConsole.init();

	// Call registered initializer for each object type
    foreach(void function() fpinit; threadInitTable)
        (*fpinit)();

    version(none) {
        void dump_proto(alias proto)() {
            mixin("std.stdio.writefln("~'"'~proto.internal_prototype.stringof~"=%x"~'"'~", cast(void*)"~proto.internal_prototype.stringof~");");
        }

        void hasproperty(alias obj)() {
            enum func=obj.HasProperty("hasOwnProperty").stringof;
            enum mixdo="std.stdio.writeln("~'"'~obj.stringof~".hasProperty="~'"'~","~func~");";
            mixin(mixdo);
            std.stdio.writeln("-------- ------------------- ---------");
        }
        std.stdio.writefln("prototype=%x",cast(void*)Dobject_prototype);
        dump_proto!Dobject_prototype;
        dump_proto!(Dobject_constructor)();
        dump_proto!(Dfunction_prototype)();
        dump_proto!(Dfunction_constructor)();
        dump_proto!(Dnumber_prototype)();
        dump_proto!(Dnumber_constructor)();

        hasproperty!Dobject_prototype;
        hasproperty!Dobject_constructor;
        hasproperty!Dfunction_prototype;
        hasproperty!Dfunction_constructor;
        hasproperty!Dboolean_prototype;
        hasproperty!Dboolean_constructor;
        hasproperty!Dnumber_prototype;
        hasproperty!Dnumber_constructor;
        hasproperty!Ddate_prototype;
        hasproperty!Ddate_constructor;
        hasproperty!DJSON_prototype;
        hasproperty!DJSON_constructor;
        hasproperty!Derror_prototype;
        hasproperty!Derror_constructor;
        hasproperty!Dregexp_prototype;
        hasproperty!Dregexp_constructor;
    }
}
