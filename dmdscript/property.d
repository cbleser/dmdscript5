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
 * Upgrading to EcmaScript 5.1 Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */


module dmdscript.property;

import dmdscript.script;
import dmdscript.value;
import dmdscript.identifier;

import dmdscript.dobject : ErrorValue, Dobject;
import dmdscript.errmsgs;
import dmdscript.text;

import dmdscript.RandAA;

import std.c.string;
//import std.stdio;

// attribute flags
enum : ushort
{
    ReadOnly       = 1<<0,
    DontEnum       = 1<<1,
    DontDelete     = 1<<2,
    DontConfig     = 1<<3,
    Internal       = 1<<4,
    Deleted        = 1<<5,
    Locked         = 1<<6,
    //   DontOverride   = 1<<7,
    KeyWord        = 1<<8,
    DebugFree      = 1<<9,       // for debugging help
    Instantiate    = 1<<10,      // For COM named item namespace support
}

struct Property
{
    ushort attributes;
    Value value;
    static d_string toInfo(ushort attributes) {
        d_string buf;

        ushort mask=1;
        bool notfirst;
        bool firstin;
        bool non;
        immutable(char)[] orSymbol() {
            scope(exit) {
                firstin=true;
            }
            return (firstin && notfirst)?"|":"";
        }
        buf~=" (";
        while(mask != 0) {
            non=false;
            switch (attributes & mask) {
            case ReadOnly:     buf~=toDstring(orSymbol~ReadOnly.stringof); break;
            case DontEnum:     buf~=toDstring(orSymbol~DontEnum.stringof); break;
            case DontDelete:   buf~=toDstring(orSymbol~DontDelete.stringof); break;
            case DontConfig:   buf~=toDstring(orSymbol~DontConfig.stringof); break;
            case Internal:     buf~=toDstring(orSymbol~Internal.stringof); break;
            case Deleted:      buf~=toDstring(orSymbol~Deleted.stringof); break;
            case Locked:       buf~=toDstring(orSymbol~Locked.stringof); break;
                //  case DontOverride: buf~=toDstring(orSymbol~DontOverride.stringof); break;
            case KeyWord:      buf~=toDstring(orSymbol~KeyWord.stringof); break;
            case DebugFree:    buf~=toDstring(orSymbol~DebugFree.stringof); break;
            case Instantiate:  buf~=toDstring(orSymbol~Instantiate.stringof); break;
            default:
                // Empty
            }
            notfirst=true;
            mask<<=1;
        }
        buf~=")";
        return buf;
    }
    d_string toInfo() {
        d_string buf;
        buf=value.toInfo;
        buf~=toInfo(attributes);
        return buf;
    }

    bool isAccessorDescriptor() const {
        // Ecma v5 8.10.1
        return (value.isAccessor && (value.setter || value.getter));
    }

    bool isDataDescriptor() const {
        // Ecma v5 8.10.2
        return (!value.isAccessor);
    }

    bool isGenericDescriptor() const {
        // Ecma v5 8.12.3
        return (!isAccessorDescriptor && !isDataDescriptor);
    }


}

extern (C)
{
/* These functions are part of the internal implementation of Phobos
 * associative arrays. It's faster to use them when we have precomputed
 * values to use.
 */

    version(none) // Not used any longer
struct Array
{
    int   length;
    void* ptr;
}

struct aaA
{
    aaA *  left;
    aaA *  right;
    hash_t hash;
    /* key   */
    /* value */
}

struct BB
{
    aaA*[] b;
    size_t nodes;       // total number of aaA nodes
}

struct AA
{
    BB* a;
    version(X86_64)
    {
    }
    else
    {
        // This is here only to retain binary compatibility with the
        // old way we did AA's. Should eventually be removed.
        int reserved;
    }
}

long _aaRehash(AA* paa, TypeInfo keyti);

/************************
 * Alternate Get() version
 */

private Property* _aaGetY(hash_t hash, Property[Value]* bb, Value* key)
{
    aaA* e;
    auto aa = cast(AA*)bb;

    if(!aa.a)
        aa.a = new BB();

    auto aalen = aa.a.b.length;
    if(!aalen)
    {
        alias aaA *pa;

        aalen = 97;
        aa.a.b = new pa[aalen];
    }

    //printf("hash = %d\n", hash);
    size_t i = hash % aalen;
    auto pe = &aa.a.b[i];
    while((e = *pe) != null)
    {
        if(hash == e.hash)
        {
            Value* v = cast(Value*)(e + 1);
            if(key.vtype == vtype_t.V_NUMBER)
            {
                if(v.vtype == vtype_t.V_NUMBER && key.number == v.number)
                    goto Lret;
            }
            else if(key.vtype == vtype_t.V_STRING)
            {
                if(v.vtype == vtype_t.V_STRING && key.string is v.string)
                    goto Lret;
            }
            auto c = key.opCmp(*v);
            if(c == 0)
                goto Lret;
            pe = (c < 0) ? &e.left : &e.right;
        }
        else
            pe = (hash < e.hash) ? &e.left : &e.right;
    }

    // Not found, create new elem
    //printf("\tcreate new one\n");
    e = cast(aaA *)cast(void*)new void[aaA.sizeof + Value.sizeof + Property.sizeof];
    std.c.string.memcpy(e + 1, key, Value.sizeof);
    e.hash = hash;
    *pe = e;

    {
        auto nodes = ++aa.a.nodes;
        //printf("length = %d, nodes = %d\n", (*aa).length, nodes);
        if(nodes > aalen * 4)
        {
            _aaRehash(aa, typeid(Value));
        }
    }

    Lret:
    return cast(Property*)(cast(void *)(e + 1) + Value.sizeof);
}

/************************************
 * Alternate In() with precomputed values.
 */

private Property* _aaInY(hash_t hash, Property[Value] bb, Value* key)
{
    size_t i;
    AA aa = *cast(AA*)&bb;

    //printf("_aaIn(), aa.length = %d, .ptr = %x\n", aa.length, cast(uint)aa.ptr);
    if(aa.a && aa.a.b.length)
    {
        //printf("hash = %d\n", hash);
        i = hash % aa.a.b.length;
        auto e = aa.a.b[i];
        while(e != null)
        {
            if(hash == e.hash)
            {
                int c;
                Value* v = cast(Value*)(e + 1);
                if(key.vtype == vtype_t.V_NUMBER && v.vtype == vtype_t.V_NUMBER &&
                    key.number == v.number) {
                    goto Lfound;
                }
                c = key.opCmp(*v);
                if(c == 0) {
                  Lfound:
                    return cast(Property*)(cast(void *)(e + 1) + Value.sizeof);
                } else {
                    e = (c < 0) ? e.left : e.right;
                }
            }
            else
                e = (hash < e.hash) ? e.left : e.right;
        }
    }

    // Not found
    return null;
}
}

/*********************************** PropTable *********************/

struct PropTable
{
    //Property[Value] table;
    package RandAA!(Value, Property) table;
    @property
    PropTable* previous() {
        Dobject prototype=owner.internal_prototype;
        if ((owner !is prototype) && prototype) {
            return prototype.proptable;
        }
        return null;
    }

    @property
    uint size() {
        return cast(uint)table.length;
    }
    private Dobject owner;

    this(Dobject owner) {
        this.owner=owner;
    }

    int opApply(int delegate(ref Property) dg)
    {
        initialize();
        int result;
        foreach(ref Property p; table)
        {
            result = dg(p);
            if(result)
                break;
        }
        return result;
    }

    int opApply(int delegate(ref Value, ref Property) dg)
    {
        initialize();
        int result;

        foreach(Value key, ref Property p; table)
        {
            result = dg(key, p);
            if(result)
                break;
        }
        return result;
    }

    /*******************************
     * Look up name and get its corresponding Property.
     * Return null if not found.
     */

    Property *getProperty(d_string name)
    {
        Property *p;
        if (table) {
            scope Value vname=Value(name);
            p = table.findExistingAlt(vname, vname.toHash);
        }
        return p;
    }

    Value* get(const Value* key, hash_t hash)
    in {
        assert(Value.calcHash(*key) == hash);
    }
    body
    {
        uint i;
        Property* p;
        PropTable* t;
        Value* _key;
        //   key.toHash();
        if (key.vtype == vtype_t.V_INTEGER) {
            Value tmp;
            tmp=key.numberToString();
            _key=&tmp;
        }
        t = &this;
        do
        {
            //writefln("\tt = %x", cast(uint)t);
            t.initialize();
            //p = *key in t.table;
            if (_key) {
                p = t.table.findExistingAlt(*_key,hash);
            } else {
                p = t.table.findExistingAlt(*key,hash);
            }
            if(p)
            {
                //TODO: what's that assert for? -- seems to run OK without it
                //bombs with range violation otherwise!
                /*try{
                        assert(t.table[*key] == p);
                   }catch(Error e){
                        writef("get(key = '%s', hash = x%x)", key.toString(), hash);
                        //writefln("\tfound");
                        p.value.dump();
                   }*/
                //p.value.dump();
                return &p.value;
            }
            t = t.previous;
        } while(t);
        //writefln("\tnot found");
        return null;                    // not found
    }
/*
    Value* get(d_uint32 index)
    {
        Value key;

        key.putVnumber(index);
        hash_t h = key.toHash;
        return get(&key, h);
    }

    Value* get(Identifier* id)
    {
        return get(id.toValue, id.toHash);
        //return get(id.value.string, id.value.hash);
    }

    Value* get(d_string name, hash_t hash)
    {
        Value key;

        key.putVstring(name);
        key.toHash(); // Calculate hash
        //    assert(key.toHash() == hash);
        return get(&key, hash);
    }
*/
    /*******************************
     * Determine if property exists for this object.
     * The enumerable flag means the DontEnum attribute cannot be set.
     */

    bool hasownproperty(const Value* key, bool enumerable)
        in {
        assert(key.hasHash);
    } body {
        //    initialize();
        Property* p;
        // key.toHash; // Make sure that the hash is calculated
        p = (table)?*key in table:null;
        return p && (!enumerable || !(p.attributes & DontEnum));
    }

    bool hasproperty(const(Value)* key)
        in {
        assert(key.hasHash);
    } body
    {
        initialize();
        int recursion_id;
        bool has(PropTable* prop) {

            if (prop.owner.wasInRecursion(recursion_id)) return false;
//            std.stdio.writef("->[%x]",cast(void*)prop.owner);
            prop.owner.setRecursion(recursion_id);
            return (*key in prop.table) != null || (previous && has(previous));
        }
        recursion_id=Dobject.newRecursion();
        return has(&this);
    }

    int hasproperty(d_string name)
    {
        Value v;
        v.putVstring(name);
        v.toHash;
        return hasproperty(&v);
    }

    static Property* getProperty(PropTable* proptable, const(Value)* key, hash_t hash, out Property* ownprop, out Dobject owner_of_prop)
        in {
        assert(key.hasHash);
    } body
    {
        int recursion_id;
        Property* find(PropTable* prop) {
            if (prop is null ||  prop.owner.wasInRecursion(recursion_id)) return null;
            prop.owner.setRecursion(recursion_id);
            Property* result=(prop.table)?(*key in prop.table):null;
            if (prop is proptable) ownprop=result; // own property is the one found in proptable
            if (result) {
                owner_of_prop=prop.owner;
                return result;
            } else {
                return find(prop.previous);
            }
        }
        recursion_id=Dobject.newRecursion();
        return find(proptable);
    }

    /**
       @param define Enables DefineOnwProperty
     */
    Value* put(const Value* key, hash_t hash, Value* value, ushort attributes, Setter set, bool define)
    in {
        assert(key.isPrimitive);
        assert(key.hasHash);
    }
    // out {
    //     assert((!owner.isExtensible || owner.isSealed) || ((*key in table) || getProperty(previous, key)));
    // }
    body
    {

        Property* p;

        //    std.stdio.writefln("key=%s define=%s value=%s attributes=%s",key.toInfo,define,value.toInfo,Property.toInfo(attributes));
        //writefln("table contains %d properties",table.length);
        //writefln("put(key = %s, hash = x%x, value = %s, attributes = x%x)", key.toString(), hash, value.toString(), attributes);
        //writefln("put(key = %s)", key.toString());

        //p = &table[*key];
        //version(none){
        //writeln(cast(void*)table);
        //p = *key in table;

        if (define) {
            if (table) p = table.findExistingAlt(*key,hash);
        } else if ( !owner.canput(key, hash, p) ) {
            std.stdio.writeln("Can't put! ",key.toInfo, " strict mode=", (CallContext.currentcc)?CallContext.currentcc.isStrictMode:false);
            if (CallContext.currentcc && CallContext.currentcc.isStrictMode) {
                ErrInfo errinfo=CallContext.currentcc.errorInfo;
                if (key.isString) {
                    if (key.string == TEXT_arguments) {
                        throw new ErrorValue(Dobject.SyntaxError(errinfo, errmsgtbl[ERR_READONLY], key.toInfo, key.toInfo));
                    }
                }
                throw new ErrorValue(Dobject.RuntimeError(errinfo, errmsgtbl[ERR_READONLY], key.toInfo));
            } else {
                return null;
            }
        }
//        p = table.findExistingAlt(*key,hash);
        if (owner.isSealed) {
            return null; // Object protected
        }
        if(p) {
            // Backfiers the attributes mask to the call value
            value.protect=p.attributes;
          Lx:
            if (value.isAccessor) {
                if (define) {
                    if (value.setter) p.value.putVSetter(value.setter);
                    if (value.getter) p.value.putVGetter(value.getter);
                }
            }
            if (p.value.isAccessor && !define) {
                if (!set) {
                    throw new ErrorValue(Dobject.ReferenceError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_NO_CONTEXT_SETGET],key.toInfo));
                }

                Value* err=set(&p.value, value, value);
                if (err) {
                    return err;
                }
                return null;
            }
            if(attributes & DontConfig && ((p.value.vtype != vtype_t.V_REF_ERROR ||
                    p.attributes & ReadOnly) && !define) )
            {
                if(p.attributes & KeyWord)
                    return null;
                if (CallContext.currentcc && CallContext.currentcc.isStrictMode) {
                    return Dobject.RuntimeError(CallContext.currentcc.errorInfo, errmsgtbl[ERR_READONLY], key.toInfo);
                }

                return &Value.vundefined;
            }

            PropTable* t = previous;
            if(t)
            {
                do
                {
                    Property* q;
                    //t.initialize();
                    //q = *key in t.table;
                    q = (table)?t.table.findExistingAlt(*key,hash):null;
                    if(q)
                    {
                        if(q.attributes & ReadOnly)
                        {
                            //p.attributes |= ReadOnly;
                            return &Value.vundefined;
                        }
                        break;
                    }
                    t = t.previous;
                } while(t);
            }

            // Overwrite property with new value
            // std.stdio.writeln("before attributes=",p.toInfo);
            Value.copy(&p.value, value);
            // p.attributes = (attributes &
            // ~(DontOverride|DontConfig)) | (p.attributes &
            // (DontDelete | DontEnum));
            if (define) {
                p.attributes = attributes;
            // } else if ( (p.attributes & DontConfig) == 0) {
            //     p.attributes = attributes;
            }
            //p.attributes = (p.attributes & (~umask))|(attributes & umask);
//(attributes & ~umask ) & (DontDelete | DontEnum |DontConfig|ReadOnly) );
            // std.stdio.writeln("after attributes=",p.toInfo);
            return null;
        }
        else {
            // if (!owner.isExtendable) {
            //     return null; // Prevent extension
            // }
            initialize();
            auto prop=Property(attributes, *value);
            table.insertAlt(*key, prop, hash);
            return null; // success
        }
    }

/* We only what to maintaine one put function in PropTable
    Value* put(d_string name, Value* value, ushort attributes, lazy Setter setter, bool define)
    {
        Value key;

        key.putVstring(name);

        //writef("PropTable::put(%p, '%ls', hash = x%x)\n", this, d_string_ptr(name), key.toHash());
        hash_t h=key.toHash();
        return put(&key, h, value, attributes, setter, define);
    }

    Value* put(d_uint32 index, Value* value, ushort attributes, bool define)
    {
        Value key;

        key.putVnumber(index);
        hash_t h=key.toHash();
        //writef("PropTable::put(%d)\n", index);
        return put(&key, h, value, attributes, null, define);
    }

    Value* put(d_uint32 index, d_string string, ushort attributes, bool define)
    {
        Value key;
        Value value;

        key.putVnumber(index);
        value.putVstring(string);
        hash_t h=key.toHash(); // Calculate hash
        return put(&key, h, &value, attributes, null, define);
    }
*/

    bool canput(const Value* key, hash_t hash, out Property* ownprop)
        in {
        assert(key.hasHash);
    } body {
        // Ecma v5 8.12.4
        if (!owner.isExtensible) return false;
        Dobject owner_of_property;
        Property* prop=getProperty(&this, key, hash, ownprop, owner_of_property);
        if (prop) {
            if (prop.value.isAccessor) {
                if (prop.value.setter is null) return false;
            } else {
                // If a prototype is configurable the set canput to true
                if ( ( (prop.attributes & DontConfig) == 0) && (owner_of_property !is owner) ) return true;
                if (prop.attributes & ReadOnly) return false;
            }
        }
        return true;
    }

/+
    bool canput(const Value* key, hash_t hash)
        in {
        assert(key.hasHash);
    } body
    {
        initialize();
        Property *p;
        PropTable *t;

        t = &this;
        do
        {
            //p = *key in t.table;
            t.initialize;
             p = t.table.findExistingAlt(*key,hash);
            if(p)
            {
                return (p.attributes & ReadOnly)
                       ? false : true;
            }
            t = t.previous;
        } while(t);
        return true;                    // success
    }
+/

    bool del(const Value* key, hash_t hash)
        in {
        assert(Value.calcHash(*key) == hash);
    } body {
        if (table is null) return true;
        Property *p;

        if (owner.isSealed) {
            return false;
        }
        //writef("PropTable::del('%ls')\n", d_string_ptr(key.toString()));
        p = *key in table;
        if(p)
        {
            if(p.attributes & DontDelete)
                return false;
            table.remove(*key);
        }
        return true;                    // not found
    }
/*
    bool del(d_string name)
    {
        Value v;

        v.putVstring(name);
        v.toHash; // Make sure that the hash is
        //writef("PropTable::del('%ls')\n", d_string_ptr(name));
        return del(&v);
    }

    bool del(d_uint32 index)
    {
        Value v;

        v.putVnumber(index);

        //writef("PropTable::del(%d)\n", index);
        return del(&v);
    }
*/
    void initialize()
    {
        if(!table)
            table = new RandAA!(Value, Property);
    }

    Property* opIn_r(Value key)
    {
        return (table)?key in table:null;
    }

    Value[] keys() {
        return table.keys;
    }

    bool isEmpty() const {
        return table is null || table.length==0;
    }

    uint length() const {
        return (table !is null)?cast(uint)table.length:0;
    }

    invariant() {
        assert(owner !is null);
    }
}
