
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

module dmdscript.identifier;

import dmdscript.script;
import dmdscript.value;
import std.c.string;

/* An Identifier is a special case of a Value - it is a V_STRING
 * and has the hash value computed and set.
 */

struct Identifier
{
    private Value    value;

    d_string toText() const
    {
        return value.string;
    }

    void opAssign(const(Identifier) id) {
        memcpy(&this.value, &id.value, Value.sizeof);

        //   this.value= id.value;
    }

    const bool opEquals(ref const (Identifier)id)
    {
        return this is id || value.string == id.value.string;
    }

    static Identifier* opCall(d_string s)
    {
        Identifier* id = new Identifier;
        id.value.putVstring(s);
        id.value.toHash();
        return id;
    }

    hash_t put(d_string s) {
        value.putVstring(s);
        return value.toHash();
    }

    hash_t toHash() const
    {
        return value.hash;
    }

    const(Value)* toValue() const {
        return cast(const(Value)*)&value;
    }

    Value* toValue() {
        return &value;
    }

    @property vtype_t vtype() const pure {
        return value.vtype;
    }
}


