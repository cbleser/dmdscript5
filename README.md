# dmdscript5

EcmaScript 262 in D-lang

This is a D2 port of the dmdscript the job was stated by Dmitry Olshansky, but this git branch is completely independent because code has restructure to fit more in to the D2 style and to port the code to 64-bit.
The code should now work in both 32 and 64bits.


The goal is to upgrade to the dmdscript to javascript 5.2.
The indention of this project is not to compete against node.js on performance but to be able to run javascript on top of D.


Works so far
-------
Most of the new functions and features in javascript 5.2
Like Array.foreach, Object.defineProperty, setter and getters

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


License
-------
See LICENSE.txt


Contact
-------

udefranettet@gmail.com
