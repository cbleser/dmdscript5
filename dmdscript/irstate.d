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
 *
 * Upgrading to EcmaScript 5.1 by Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */


module dmdscript.irstate;

import std.c.stdarg;
import std.c.stdlib;
import std.c.string;
import std.outbuffer;
import core.memory;
import core.stdc.stdio;

import std.stdio;

import dmdscript.script;
import dmdscript.statement;
import dmdscript.opcodes;
import dmdscript.ir;
import dmdscript.identifier;



// The state of the interpreter machine as seen by the code generator, not
// the interpreter.

struct IRstate
{
    OutBuffer      codebuf;             // accumulate code here
    Statement      breakTarget;         // current statement that 'break' applies to
    Statement      continueTarget;      // current statement that 'continue' applies to
    ScopeStatement scopeContext;        // current ScopeStatement we're inside
    uint[]         fixups;

    //void next();	// close out current Block, and start a new one

    private uint locali = 1;            // leave location 0 as our "null"
    private uint nlocals = 1;

    uint getNlocals() const {
        return nlocals;
    }
    void ctor()
    {
        codebuf = new OutBuffer();
    }

    void validate()
    {
        assert(codebuf.offset <= codebuf.data.length);
        if(codebuf.data.length > codebuf.data.capacity)
            printf("ptr %p, length %d, capacity %d\n", codebuf.data.ptr, codebuf.data.length, core.memory.GC.sizeOf(codebuf.data.ptr));
        assert(codebuf.data.length <= codebuf.data.capacity);
        for(uint u = 0; u < codebuf.offset; )
        {
            IR* code = cast(IR*)(codebuf.data.ptr + u);
            assert(code.opcode <= code.opcode.max);
            u += IR.size(code.opcode) * 4;
        }
    }

    /**********************************
     * Allocate a block of local variables, and return an
     * index to them.
     */

    uint alloc(unsigned nlocals)
    {
        uint n;

        n = locali;
        locali += nlocals;
        if(locali > this.nlocals)
            this.nlocals = locali;
        assert(n);
        return n * INDEX_FACTOR;
    }

    /****************************************
     * Release this block of n locals starting at local.
     */

    void release(unsigned local, unsigned n)
    {
        /+
            local /= INDEX_FACTOR;
            if (local + n == locali)
                locali = local;
         +/
    }

    uint mark()
    {
        return locali;
    }

    void release(uint i)
    {
        //locali = i;
    }

    static unsigned combine(Loc loc, uint opcode)
    {
        return (loc << 16) | opcode;
    }

    /***************************************
     * Generate code.
     */

    void gen0(Loc loc, IRcode opcode)
    {
        codebuf.write(combine(loc, opcode));
    }

    void gen1(Loc loc, IRcode opcode, unsigned arg)
    {
	    enum package_size=2*unsigned.sizeof;
        codebuf.reserve(package_size);
        version(all)
        {
            // Inline ourselves for speed (compiler doesn't do a good job)
            unsigned *data = cast(unsigned *)(codebuf.data.ptr + codebuf.offset);
            codebuf.offset += package_size;
            data[0] = combine(loc, opcode);
            data[1] = arg;
        }
        else
        {
            codebuf.write4n(combine(loc, opcode));
            codebuf.write4n(arg);
        }
    }

  version(D_LP64) {
	// Note. unsigned and double doesn't to align byte wise in 64bit
      void gen2(Loc loc, IRcode opcode, unsigned arg1, double arg2)
      {
          codebuf.reserve(3*unsigned.sizeof);
          codebuf.write(combine(loc,opcode));
          codebuf.write(arg1);
          codebuf.write(arg2);
      }
  }
    void gen2(Loc loc, IRcode opcode, unsigned arg1, unsigned arg2) {
        enum package_size=3*unsigned.sizeof;
        codebuf.reserve(package_size);
        version(all)
        {
            // Inline ourselves for speed (compiler doesn't do a good job)
            unsigned *data = cast(unsigned *)(codebuf.data.ptr + codebuf.offset);
            codebuf.offset += package_size;
            data[0] = combine(loc, opcode);
            data[1] = arg1;
            data[2] = arg2;
        }
        else
        {
            codebuf.write4n(combine(loc, opcode));
            codebuf.write4n(arg1);
            codebuf.write4n(arg2);
        }
    }

  version(D_LP64) {
    void gen3(Loc loc, IRcode opcode, unsigned arg1, unsigned arg2, double arg3)
	{
	  codebuf.reserve(4*unsigned.sizeof);
	  codebuf.write(combine(loc,opcode));
	  codebuf.write(arg1);
	  codebuf.write(arg2);
	  codebuf.write(arg3);
	}

  }
    void gen3(Loc loc, IRcode opcode, unsigned arg1, unsigned arg2, unsigned arg3)
    {
	    enum package_size=4*unsigned.sizeof;
        codebuf.reserve(package_size);
        version(all)
        {
            // Inline ourselves for speed (compiler doesn't do a good job)
            unsigned *data = cast(unsigned *)(codebuf.data.ptr + codebuf.offset);
            codebuf.offset += package_size;
            data[0] = combine(loc, opcode);
            data[1] = arg1;
            data[2] = arg2;
            data[3] = arg3;
        }
        else
        {
            codebuf.write4n(combine(loc, opcode));
            codebuf.write4n(arg1);
            codebuf.write4n(arg2);
            codebuf.write4n(arg3);
        }
    }

    void gen4(Loc loc, IRcode opcode, unsigned arg1, unsigned arg2, unsigned arg3, unsigned arg4)
    {
	    enum package_size=5*unsigned.sizeof;
        codebuf.reserve(package_size);
        version(all)
        {
            // Inline ourselves for speed (compiler doesn't do a good job)
            unsigned *data = cast(unsigned *)(codebuf.data.ptr + codebuf.offset);
            codebuf.offset += package_size;
            data[0] = combine(loc, opcode);
            data[1] = arg1;
            data[2] = arg2;
            data[3] = arg3;
            data[4] = arg4;
        }
        else
        {
            codebuf.write4n(combine(loc, opcode));
            codebuf.write4n(arg1);
            codebuf.write4n(arg2);
            codebuf.write4n(arg3);
            codebuf.write4n(arg4);
        }
    }

    void gen(Loc loc, uint opcode, uint argc, ...)
    {
	  codebuf.reserve((1 + argc) * unsigned.sizeof);
	  codebuf.write(combine(loc, opcode));
	  for(uint i = 1; i <= argc; i++)
	  {
		codebuf.write(va_arg!(unsigned)(_argptr));
	  }
    }

    void pops(uint npops)
    {
        while(npops--)
            gen0(0, IRcode.IRpop);
    }

    /******************************
     * Get the current "instruction pointer"
     */

    uint getIP()
    {
        if(!codebuf)
            return 0;
        return cast(uint)(codebuf.offset / unsigned.sizeof);
    }

    /******************************
     * Patch a value into the existing codebuf.
     */

    void patchJmp(uint index, size_t value)
    {
        assert((index + 1) * 4 < codebuf.offset);
        (cast(unsigned *)(codebuf.data))[index + 1] = value - index;
    }

    /*******************************
     * Add this IP to list of jump instructions to patch.
     */

    void addFixup(uint index)
    {
        fixups ~= index;
    }

    /*******************************
     * Go through the list of fixups and patch them.
     */

    void doFixups()
    {
        uint i;
        uint index;
        size_t value;
        Statement s;

        for(i = 0; i < fixups.length; i++)
        {
            index = fixups[i];
            assert((index + 1) * 4 < codebuf.offset);
            s = (cast(Statement *)codebuf.data)[index + 1];
            value = s.getTarget();
            patchJmp(index, value);
        }
    }


    void optimize()
    {
        // Determine the length of the code array
        IR *c;
        IR *c2;
        IR *code;
        uint length;
        uint i;
        code = cast(IR *)codebuf.data;
        for(c = code; c.opcode != IRcode.IRend; c += IR.size(c.opcode))
        {
        }
        length = cast(uint)(c - code + 1);

        // Allocate a bit vector for the array
        byte[] b = new byte[length]; //TODO: that was a bit array, maybe should use std.container

        // Set bit for each target of a jump
        for(c = code; c.opcode != IRcode.IRend; c += IR.size(c.opcode))
        {
            with (IRcode) switch(c.opcode)
            {
            case IRjf:
            case IRjt:
            case IRjfb:
            case IRjtb:
            case IRjmp:
            case IRjlt:
            case IRjle:
            case IRjltc:
            case IRjlec:
            case IRtrycatch:
            case IRtryfinally:
            case IRnextscope:
            case IRnext:
            case IRnexts:
                b[(c - code) + (c + 1).offset] = true;
                break;
            default:
                break;
            }
        }

        // Allocate array of IR contents for locals.
        IR*[] local;
        IR*[] p1 = null;

        // Allocate on stack for smaller arrays
        IR** plocals;
        if(nlocals < 128)
            plocals = cast(IR * *)alloca(nlocals * local[0].sizeof);

        if(plocals)
        {
            local = plocals[0 .. nlocals];
            local[] = null;
        }
        else
        {
            p1 = new IR *[nlocals];
            local = p1;
        }

        // Optimize
        for(c = code; c.opcode != IRcode.IRend; c += IR.size(c.opcode))
        {
		  uint offset = cast(uint)(c - code);

            if(b[offset])       // if target of jump
            {
                // Reset contents of locals
                local[] = null;
            }

            with(IRcode) switch(c.opcode)
            {
            case IRnop:
                break;

            case IRnumber:
            case IRstring:
            case IRboolean:
                local[(c + 1).index / INDEX_FACTOR] = c;
                break;

            case IRadd:
            case IRsub:
            case IRcle:
                local[(c + 1).index / INDEX_FACTOR] = c;
                break;

            case IRputthis:
                local[(c + 1).index / INDEX_FACTOR] = c;
                goto Lreset;

            case IRputscope:
                local[(c + 1).index / INDEX_FACTOR] = c;
                break;

            case IRgetscope:
            {
                Identifier* cs = (c + 2).id;
                IR *cimax = null;
                for(i = nlocals; i--; )
                {
                    IR *ci = local[i];
                    if(ci &&
                       (ci.opcode == IRgetscope || ci.opcode == IRputscope) &&
                       (ci + 2).id.toText == cs.toText
                       )
                    {
                        if(cimax)
                        {
                            if(cimax < ci)
                                cimax = ci;     // select most recent instruction
                        }
                        else
                            cimax = ci;
                    }
                }
                if(1 && cimax)
                {
                    //writef("IRgetscope . IRmov %d, %d\n", (c + 1).index, (cimax + 1).index);
                    c.opcode = IRmov;
                    (c + 2).index = (cimax + 1).index;
                    local[(c + 1).index / INDEX_FACTOR] = cimax;
                }
                else
                    local[(c + 1).index / INDEX_FACTOR] = c;
                break;
            }

            case IRnew:
                local[(c + 1).index / INDEX_FACTOR] = c;
                goto Lreset;

            case IRcallscope:
            case IRputcall:
            case IRputcalls:
            case IRputcallscope:
            case IRputcallv:
            case IRcallv:
                local[(c + 1).index / INDEX_FACTOR] = c;
                goto Lreset;

            case IRmov:
                local[(c + 1).index / INDEX_FACTOR] = local[(c + 2).index / INDEX_FACTOR];
                break;

            case IRput:
            case IRpostincscope:
            case IRaddassscope:
                goto Lreset;

            case IRjf:
            case IRjfb:
            case IRjtb:
            case IRjmp:
            case IRjt:
            case IRret:
            case IRjlt:
            case IRjle:
            case IRjltc:
            case IRjlec:
                break;

            default:
                Lreset:
                // Reset contents of locals
                local[] = null;
                break;
            }
        }

        delete p1;

        //return;
        // Remove all IRnop's
        for(c = code; c.opcode != IRcode.IRend; )
        {
            unsigned offset;
            unsigned o;
            unsigned c2off;

            if(c.opcode == IRcode.IRnop)
            {
			    offset = cast(unsigned)(c - code);
                for(c2 = code; c2.opcode != IRcode.IRend; c2 += IR.size(c2.opcode))
                {
                    with(IRcode) switch(c2.opcode)
                    {
                    case IRjf:
                    case IRjt:
                    case IRjfb:
                    case IRjtb:
                    case IRjmp:
                    case IRjlt:
                    case IRjle:
                    case IRjltc:
                    case IRjlec:
                    case IRnextscope:
                    case IRtryfinally:
                    case IRtrycatch:
                        c2off = cast(unsigned)(c2 - code);
                        o = c2off + (c2 + 1).offset;
                        if(c2off <= offset && offset < o)
                            (c2 + 1).offset--;
                        else if(c2off > offset && o <= offset)
                            (c2 + 1).offset++;
                        break;
                    /+
                                        case IRtrycatch:
                                            o = (c2 + 1).offset;
                                            if (offset < o)
                                                (c2 + 1).offset--;
                                            break;
                     +/
                    default:
                        continue;
                    }
                }

                length--;
                memmove(c, c + 1, (length - offset) * unsigned.sizeof);
            }
            else
                c += IR.size(c.opcode);
        }
    }
}
