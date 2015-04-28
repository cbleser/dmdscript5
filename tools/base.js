

if (typeof console === 'undefined') {
    console={};
    console.log=print;
}

$ERROR=console.log;

var runTestCase=function(testfunc) {
    console.log(testfunc());
};

var __globalObject=Function("return this;")();
function fnGlobalObject() {
     return __globalObject;
}

//-----


