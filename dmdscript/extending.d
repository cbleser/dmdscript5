/* Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * extending.d - experimental facility for ease of extending DMDScript
 *
 * written by Dmitry Olshansky 2010
 *
 * Upgrading to EcmaScript 5.1 by Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */
import dmdscript.script;
import dmdscript.value;
import dmdscript.dobject;
import dmdscript.darray;
import dmdscript.dfunction;
import dmdscript.dnative;
import dmdscript.program;
import dmdscript.property;
import dmdscript.threadcontext;
import dmdscript.errmsgs;
import dmdscript.text;

import std.typecons;
import std.traits;
import std.typetuple;
import std.file;
//import core.exception;
import std.conv;

T convert(T)(Value* v){
    static if (is(T == double) || is(T == float)) {
		return v.toNumber();
    } else static if(is(T : int)){
		return v.toInt32();
    } else static if(is(T : const(char)[] )) {
                return fromDstring(v.toText);
    } else static if(is(T : const(wchar)[]) ){
        return v.toText();
    } else static if(is(T : Dobject)) {
        return v.toObject();
    } else{
            assert(0,"Type "~T.stringof~" not supported");
    }
}

void convertPut(T)(ref T what,Value* v){
    static if(isIntegral!T || isFloatingPoint!T){
        v.putVnumber(what);
    }
    else {
        *v=what;
    }
}

//experimental stuff, eventually will be moved to the main library
void extendGlobal(alias fn)(Program pg, d_string name)
if(isCallable!fn) {
    alias ParameterTypeTuple!fn Args;
    alias ReturnType!fn R;
    alias staticMap!(Unqual,Args) Uargs;
    static Value* embedded(Dobject pthis, CallContext* cc,
        Dobject othis, Value* ret, Value[] arglist){
        Tuple!(Uargs) tup;
        try {
            tup = convertAll!(Uargs)(arglist);
        }
        catch (core.exception.RangeError e) {
            ret.putVundefined();
            return Dobject.RuntimeError(cc.errorInfo,
                errmsgtbl[ERR_TOO_FEW_ARGUMENTS], tup.length, arglist.length);
        }
        if(arglist.length < tup.length){
            auto len = arglist.length;
            arglist.length = tup.length;
            arglist[len .. $] = Value.vundefined;
        }
        arglist = arglist[0..tup.length];

        static if(is(R == void)){
            fn(tup.expand);
        }else{
            R r = fn(tup.expand);
            convertPut(r,ret);
        }
        return null;
    }
    NativeFunctionData[] nfd = [
        {
            name,
            &embedded,
            Args.length
        }
    ];
    DnativeFunction.init(pg.callcontext.global,nfd,DontEnum);
}

void fitArray(T...)(ref Value[] arglist){
    enum staticLen = T.length;
    if(arglist.length < staticLen){
        auto len = arglist.length;
        arglist.length = staticLen;
        arglist[len .. $] = Value.vundefined;
    }
    arglist = arglist[0..staticLen];
}

void extendMethod(T,alias fn)(Dobject obj, string name)
if(is(T == class) && isCallable!fn){
    alias ParameterTypeTuple!fn Args;
    alias ReturnType!fn R;
    enum contextcaller= ( (Args.length >= 3) && is(Args[0] == CallContext*) && is(Args[1] : Dobject) && is(Args[2] == Value*) && is(R == Value*) );
    alias staticMap!(Unqual,Args) Uargs;

    static Value* embedded(Dobject pthis, CallContext* cc,
        Dobject othis, Value* ret, Value[] arglist){
        static if(Uargs.length){
            static if (contextcaller) {
                // Remove the context argumets from the arglist
                Tuple!(Uargs[3..$]) tup;
                try {
                    tup = convertAll!(Uargs[3..$])(arglist);
                }
                catch (core.exception.RangeError e) {
                    ret.putVundefined();
                    return Dobject.RuntimeError(cc.errorInfo,
                        errmsgtbl[ERR_TOO_FEW_ARGUMENTS], tup.length, arglist.length);
                }

                fitArray(arglist);
            }
            else {
                Tuple!(Uargs) tup;
                try {
                     tup = convertAll!(Uargs)(arglist);
                }
                catch (core.exception.RangeError e) {
                    ret.putVundefined();
                    ErrInfo errinfo=cc.errorInfo;
                    std.stdio.writefln("message=%s", errinfo.message);
                    return Dobject.RuntimeError(cc.errorInfo,
                        errmsgtbl[ERR_TOO_FEW_ARGUMENTS], tup.length, arglist.length);
                }

                fitArray(arglist);
            }
        }

        assert(cast(T)othis,"Wrong this pointer in external func ");
        static if (is(R == void)) {
            enum dg_return="";
        }
        else {
            enum dg_return="return ";
        }
        enum dg_call="(cast(T)othis).wrapped."~(&fn).stringof[2..$];
        static if (contextcaller) {
            static if(Uargs.length>3) {
                enum dg_args="(cc, othis, ret, tup.expand);";
            }
            else {
                enum dg_args="(cc, othis, ret);";
            }
        }
        else {
            static if (Uargs.length) {
                enum dg_args="(tup.expand);";
            }
            else {
                enum dg_args="();";
            }
        }
        enum dg_code=dg_return~dg_call~dg_args;
        auto dg = (){ mixin(dg_code); };
//        pragma(msg,"dg_code ="~dg_code);
        Value* result;
        static if (contextcaller) {
            result=dg();
        }
        else {
            static if(is(R == void)){
                dg();
            }else{
                R r= dg();
                convertPut(r,ret);
            }
        }
        return result;
    }
    NativeFunctionData[] nfd = [
        {
            toDstring(name),
            &embedded,
            Args.length
        }
    ];
    DnativeFunction.init(obj,nfd,DontEnum);
}

class Declare(Which,d_string ClassName,Base=Dobject): Base{
    Which wrapped;
    static Declare _prototype;
    static Constructor _constructor;
    static if (is(typeof(Which.__ctor))) {
        alias ParameterTypeTuple!(Which.__ctor) ConstructorArgs;
    }
    else {
        alias void ConstructorArgs;
        // pragma(msg, [__traits(derivedMembers, Which)].stringof);
        // pragma(msg, [__traits(allMembers, Which)].stringof);

        static assert(0,Which.stringof~" must have an constructor");
    }
    static class Constructor: Dfunction{
        this(){
            super(ConstructorArgs.length, Dfunction_prototype);
            name = ClassName;
        }

        override Value* Construct(CallContext *cc, Value *ret, Value[] arglist){
            static if(ConstructorArgs.length == 0) {
                Dobject o = new Declare(_prototype);
            }
            else {
                fitArray!(ConstructorArgs)(arglist);
                Dobject o = new Declare(convertAll!(UConstructorArgs)(arglist).expand);
            }
            ret.putVobject(o);
            return null;
        }

        override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist){
            return Construct(cc,ret,arglist);
        }

    }
    static void init(){
         _prototype = new Declare(Base.getPrototype());
         _constructor = new Constructor();
        _prototype.Put("constructor", _constructor, DontEnum);
        _constructor.Put("prototype", _prototype, DontEnum | DontDelete | ReadOnly);
        ctorTable[ClassName] = _constructor;
    }
    static this(){
        threadInitTable ~= &init;
    }

    private this(Dobject prototype){
        super(prototype);
        classname = ClassName;
        static if (is(Which == struct)) {
            wrapped=wrapped.init;
        }
        else {
            wrapped=new Which();
        }
    }
    alias staticMap!(Unqual,ConstructorArgs) UConstructorArgs;
    static if (ConstructorArgs.length == 0) {
        this(){
            super(_prototype);
            static if (is(Which == struct)) {
                wrapped=wrapped.init;
            }
            else {
                wrapped=new Which();
            }
        }
    }
    else {
        this(ConstructorArgs args){
            super(_prototype);
            static if ( is(Which == struct) ){
                wrapped = Which(args);
            }
            else static if ( is(Which == class) ) {
                wrapped = new Which(args);
            }
        }
    }
    static void methods(Methods...)(){
        static if(Methods.length >= 1){
             extendMethod!(Declare,Methods[0])(_prototype,(&Methods[0]).stringof[2..$]);

             methods!(Methods[1..$])();
        }
    }
}


// Something fishy module unittest not executed if it is not placed in a class
class Unittest {
        version(none)
    unittest {

        struct A {
            // String argument check
            int d_val;
            this(int val) {
                d_val=val;
            }
            int get_val() {
                return d_val;
            }
            void check_hugo(string a) {
                assert(a == "hugo");
            }
        }
        Program p=new Program;
        alias Declare!(A,"A") jsA;
        jsA.methods!(
            A.get_val,
            A.check_hugo
            )();
        auto src1=
            "var a=new A(10);\n"
            "console.log(a.get_val())"
            ""
            "A.check_hugo('hugo');\n"
            ""
            ;
        p.compile("Unittest A", src1, null);
        p.execute(null);
        std.stdio.writeln("------- unittest end ----");

    }
    unittest {
        // Test of struct with a constructor with no arguments
        struct B {
            // The default constructor must be disabled if it has no arguments
            this() @disable ;
            int z;
            int inc(int x) {
                return x+1;
            }
        }
        Program p=new Program;
        alias Declare!(B,"B") jsB;
        jsB.methods!(
            B.inc
            )();
        auto src1=
            "var x=1;\n"
            "var b=new B();\n"
            "var y=b.inc(x);\n"
            "assert(y === 2);"
            "console.log(y);\n"
            ;
        p.compile("Unittest B", src1, null);
        p.execute(null);
        std.stdio.writeln("------- unittest end ----");
    }

}

auto convertAll(Args...)(Value[] dest){
    static if(Args.length > 1){
        return tuple(convert!(Args[0])(&dest[0]),convertAll!(Args[1..$])(dest[1..$]).expand);
    }
    else {
        return tuple(convert!(Args[0])(&dest[0]));
    }
}

class DarrayNative(T, A=T[]) : Darray {
    private A narray;
    A opAssign(A rhs) {
        narray=rhs;
        return narray;
    }
    this() {
        this(getPrototype());
//        vlength.putVSetter(null);
        Put(TEXT_length, &vlength, DontDelete|DontEnum, true);
    }
    this(Dobject prototype) {
        super(prototype);
//        vlength.putVSetter(null);
        Put(TEXT_length, &vlength, DontDelete|DontEnum, true);
    }

    @property override uint ulength() {
        return cast(uint)narray.length;
    }

    override Value* put(Value* key, Value* value, ushort attributes, Setter set, bool define, hash_t hash=0) {
        d_uint32 index;
        Value* ret=new Value;
        if ( key.isArrayIndex(index) ) {
            try {
                narray[index]=value.get!T;
            }
            catch ( core.exception.RangeError e ) {
                ret.putVundefined();
                return RangeError(CallContext.currentcc.errorInfo, ERR_ARRAY_LEN_OUT_OF_BOUNDS, index);
            }
        }
        else {
            ret=super.put(key, value, attributes, set, define, hash);
        }
        return ret;
    }
    override Value* get(Value* key, hash_t hash=0) {
        d_uint32 index;
        Value* ret=new Value;
        if ( key.isArrayIndex(index) ) {
            try {
                *ret=narray[index];
            }
            catch ( core.exception.RangeError e ) {
                ret.putVundefined();
                return RangeError(CallContext.currentcc.errorInfo, ERR_ARRAY_LEN_OUT_OF_BOUNDS, index);
            }
        }
        else {
            return super.get(key, hash);
        }
        return ret;
    }
    override d_string toSource(Dobject root) {
        d_string buf;
        bool any=false;
        buf = "{";
        foreach(int i, a; narray) {
            if(any)
                buf ~= ",\n";
            any = true;
            buf ~= to!d_string(i);
            buf ~= " : ";
            buf ~= to!d_string(a);
        }

        buf ~= "}";
        return buf;
    }

}
