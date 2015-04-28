/* jslint */
/*
print("Calling extended function...");
println(mul(2,2,4));
var a = new A(42);//extended method
a.f("Test it");
a.g("Test it again");
a.h(42);
a.h1(2,4);
println("f1="+a.f1(10));


var x=5;
// We return a test B object from A
var o = a.getObj(7);
println(typeof o);
println("o.k("+x+")="+o.k(x));
a.objarg(o);
a.objarg(function(x) {console.log("callback:"+x); return x*x;});
a.callbacktest(function(x) {console.log("callback:"+x); return x*x;});

a.f1(10,20);

try {
    a.f1();
}
catch (e) {
    console.log(e.message);
}
var c=new C("Hugo");
console.log(c.getName());

var c1=new C("Borge");
console.log(c1.getName());

var d=new D(19);
console.log(typeof d);
console.log(typeof d.k);
console.log(typeof d.another);


var X=A;
var aa= new X(23);
console.log(typeof a.f1);
console.log(typeof aa.f1);
console.log(aa instanceof A);

console.log("b="+typeof b);
//var b = new B(19);
//var x = 6;
var b= new B(19);
console.log("b="+typeof b);
console.log(b instanceof B);
console.log("this should be a function but is "+typeof b.k);
console.log("this should be a function but is "+typeof b.another);
//println("B.k("+x+")="+b.k(x));

var cc=new CC();
cc.set_x(7);
console.log(cc.func(7));
*/
var d=new D(19);

console.log(typeof d.array(7));
var da=d.array(7);

console.log("da instanceof Array "+(da instanceof Array));
for(var i=0; i<7; i++) {
    console.log(da[i]);
}
console.log(da);
console.log(Array.isArray(da));
var ja=[1, 2, 3, 4, 5, 6, 7];
console.log(ja);
console.log(ja);
console.log(Array.isArray(ja));
console.log(typeof ja.forEach);
console.log(typeof da.forEach);
console.log(ja.length);
console.log(da.length);

console.log("foreach on native array");
da.forEach(function(a) {
    console.log(a);
});
