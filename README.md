# dmdscript5

EcmaScript 262 in D-lang

This is a D2 port of the dmdscript the job was stated by Dmitry Olshansky, but this git branch is completely independent because code has restructure to fit more in to the D2 style and to port javasctipt 5.1.

The code has also be change to fit both both 32 and 64bits.

The goal is to upgrade to the dmdscript to javascript 5.1.
The indention of this project is not to compete against node.js on performance but to be able to run javascript on top of D.


Works so far
-------
Most of the new functions and features in javascript 5.1
Like Array.forEach, Object.defineProperty, setter and getters

Installations
-------

Linux

    cd PathToDmdscript
    make all

To run the examples

    make run

Examples
-------

You can find examples in ./samples

Controlling build flow
-------

If you want to use a specific D2 compiler you can write.
    make DC=gdmd run


Regression test
-------
You can run the Ecma262 testcases if check out https://github.com/tc39/test262.git

    cd PathToDmdscript
    git clone https://github.com/tc39/test262.git
    make test262

The will run a long list of tests and you can find the result in test262_extended.log

This takes a while so if you only want to look run a group of test you can write

    make SUBTEST=test/built-ins/Object/ test262



License
-------
See LICENSE.txt


Contact
-------

udefranettet@gmail.com
