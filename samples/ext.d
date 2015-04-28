module samples.ext;
import dmdscript.program;
import dmdscript.value;
import dmdscript.script;
import dmdscript.extending;
import dmdscript.dobject;

import std.stdio;
import std.typecons;
import std.stdio;

int func(int a,int b){ return a*b;  }

alias Declare!(A,"A") jsA;
alias Declare!(B,"B") jsB;
alias Declare!(D, "D") jsD;
alias Declare!(C, "C") jsC;

struct A{
    int magic;
    this(int m){
        magic = m;
        std.stdio.writefln("Create A(%s) ",magic);
    }
    void f(string a){
        writeln(magic,":",a);
    }
    void g(string a){
        writeln(magic*2,":",a);
    }
    void h(d_number a){
        writeln(magic,":",a);
    }
    void h1(d_number a, d_number b){
        writeln(magic,":",a*b);
    }

    d_number f1(d_number x) {
        return x*x;
    }
    Dobject getObj(int x) {
        return new jsB(5);
    }
    void objarg(Dobject obj) {
        writefln("obj=%s",obj);
    }
    Value* callbacktest(CallContext* cc, Dobject othis, Value* ret, Dobject cb) {
        writefln("func=%s", cb);
        Value[1] args;
        args[0]=13;
        Value* result=cb.Call(cc, othis, ret, args);
        std.stdio.writefln("return value from callback %s", ret.toNumber());
        return result;
    }
}

struct B {
    int y;
    this(int y) {
        this.y=y;
        std.stdio.writefln("Create B(%s) ",y);
    }
    d_number k(d_number x) {
        return x+y;
    }
    int another(int z) {
        return z*z;
    }
}

struct C {
    string name;
    this(string name) {
        this.name=name;
    }
    string getName() {
        return name;
    }
}


struct D {
    int y;
    this(int y) {
        this.y=y;
        std.stdio.writefln("Create D(%s) ",y);
    }
    d_number k(d_number x) {
        return x+y;
    }
    int another(int z) {
        return z*z;
    }
    Dobject array(int s) {
        auto result=new DarrayNative!(int);
        int[] array=new int[s];
        foreach(int i,ref a;array) {
            a=i+1;
        }
        result=array;
        return result;
    }
}

class CC {
    int x;
    void set_x(int y) {
        this.x=y;
    }
    int func(int y) {
        return x*y;
    }
    this() {
        x=-1;
    }
}

void main(){
    Program p = new Program;

    extendGlobal!func(p,"mul");
    auto src  = cast(string)std.file.read("ext.js");
    jsA.methods!(
            A.f,
            A.g,
            A.h,
            A.h1,
            A.f1,
            A.getObj,
            A.objarg,
            A.callbacktest
            )();
    jsB.methods!(
        B.k,
        B.another
        )();
    jsC.methods!(
        C.getName
        )();
    jsD.methods!(
        D.k,
        D.another,
        D.array
        )();
    alias Declare!(CC, "CC") jsCC;
    jsCC.methods!(
        CC.set_x,
        CC.func
        )();
    //   jsCC.allMethods();
    //      .methods!(A.g)();
/*
    Declare!(A,"A").methods!(A.h)();
    Declare!(A,"A").methods!(A.h1)();
    Declare!(A,"A").methods!(A.f1)();
*/

    p.compile("TestExtending",src,null);
    // p.printfunc; // Prints the opcodes
    // dmdscript.opcodes.IR.trace=true;
    p.execute(null);
}
