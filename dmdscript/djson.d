module dmdscript.djson;

import std.stdio;

import dmdscript.value;
import dmdscript.dfunction;
import dmdscript.dobject;
import dmdscript.darray;
import dmdscript.script;
import dmdscript.text;
import dmdscript.errmsgs;
import dmdscript.threadcontext;
import dmdscript.property;
import dmdscript.dnative;

/* ===================== DJSON_constructor ==================== */

class DJSONConstructor : Dfunction
{
    this()
    {
        super(0, Dfunction_prototype);
        name = TEXT_JSON;

        static enum NativeFunctionData nfd[] =
        [
            { TEXT_parse, &DJSON_parse, 1 },
            { TEXT_stringify, &DJSON_stringify, 2 },
        ];

        DnativeFunction.init(this, nfd, DontEnum|DontDelete);
    }

  override Value* Construct(CallContext *cc, Value *ret, Value[] arglist)
  {
	// ECMA 15.9.3<--- JSON
	Dobject o;
	o = new DJSON();
	ret.putVobject(o);
	return null;
  }

  override Value* Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
  {
	// ECMA 15.9.2
	// return string as if (new Date()).toText
	return null;
  }
}


/* ===================== JSON.constructor functions ==================== */

/* ===================== DJSON_prototype ==================== */

class DJSONPrototype : DJSON
{
  this()
  {
	super(Dobject_prototype);

	Dobject f = Dfunction_prototype;

	Put(TEXT_constructor, DJSON_constructor, DontEnum);

	static enum NativeFunctionData nfd[] =
        [
			//           { TEXT_toString, &Ddate_prototype_toString, 0 },
        ];

	DnativeFunction.init(this, nfd, DontEnum | DontDelete);
  }
}

/* ===================== DJSON.prototype ==================== */



/* ===================== DJSON ==================== */

class DJSON : Dobject
{
  this()
  {
	super(DJSON.getPrototype());
	classname = TEXT_JSON;
	//        value.putVnumber(n);
  }

  this(Dobject prototype)
  {
	super(prototype);
	classname = TEXT_JSON;
  }

  static void init()
  {
	DJSON_constructor = new DJSONConstructor();
	DJSON_prototype = new DJSONPrototype();

	DJSON_constructor.Put(TEXT_prototype, DJSON_prototype,
		DontEnum | DontDelete | ReadOnly);

	assert(DJSON_prototype.length != 0);
  }

  static Dfunction getConstructor()
  {
	return DJSON_constructor;
  }

  static Dobject getPrototype()
  {
	return DJSON_prototype;
  }
}


Value* DJSON_parse(Dobject pthis, CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
{
  // ECMA 15.9.4.2 <--- JSON
  d_string s;
  Dobject o;

  if(arglist.length == 0)
	o = null;
  else {
      s = arglist[0].toText;
	//        o = parseJSONString(cc, s);
  }

  ret.putVobject(o);
  return null;
}


// d_time parseJSONString(CallContext *cc, string s)
// {
//     return dmdscript.date.parse(s);
// }

immutable(char)[] stringifyJSONObject(CallContext* cc, Dobject o) {
  return "";
}

Value* DJSON_stringify(Dobject pthis, CallContext *cc, Dobject othis, Value *ret, Value[] arglist)
{
    mixin Dobject.SetterT;
    // ECMA v5.1 15.12.3
    d_string buf;
    d_string gap; // The gap set by spacer
    Dfunction replacerFunction;
    Darray propertyList;
    d_string key="1";
    int recursion;
    ret.putVundefined;
    Value* stringify(ref d_string buf, Value* val, d_string indent) {
        int any;
        Value* result;
        if (replacerFunction) {
            Value[] replacerArgs=new Value[2];
            replacerArgs[0]=key;
            replacerArgs[1]=*val;
            Value ret;
            replacerFunction.Call(cc, othis, &ret, replacerArgs);
            val=&ret;
        } else if (propertyList) {
            Value item;
            with(vtype_t) switch (val.vtype) {
                case V_NULL:
                case V_BOOLEAN:
                case V_NUMBER:
                case V_OBJECT:
                    item=val.toText;
                    propertyList.Put(key, &item, 0);
                    break;
                default:
                    /* empty */
                }
        }
        with(vtype_t) switch (val.vtype) {
            case V_NULL:
            case V_BOOLEAN:
            case V_NUMBER:
            case V_UNDEFINED:
                buf ~= val.toText;
                break;
            case V_STRING:
                buf ~= '"' ~ val.toText ~ '"';
                break;
            case V_OBJECT:
                buf ~= "{";
                any = 0;
                Dobject othis=val.object;
                if (othis.wasInRecursion(recursion)) {
                    return Dobject.RuntimeError(cc.errorInfo, errmsgtbl[ERR_CIRCULAR_STRUCTURE], TEXT_JSON);
                }
                othis.setRecursion(recursion);
                foreach(Value prop, Property p; othis) {
                    if(!(p.attributes & (DontEnum | Deleted))) {
                        if(any) buf ~= ',';
                        any = 1;
                        key=prop.toText;
                        buf ~= '"' ~ key ~ '"' ;
                        buf ~= ':';
                        result=stringify(buf, &p.value, indent~gap);
                        if (result)
                            return result;
                    }
                }
                buf ~= '}';
                break;
            default:
                val.throwRefError();
            }
        return null;
    }
    //  writef("othis.toText=%s\n", othis.toText);
    if (arglist.length >= 1) {
        // Replacer argument
        if ( (arglist.length >= 2) && (arglist[1].isObject()) ) {
            if ( (replacerFunction=Dfunction.isFunction(&arglist[1])) is null ) {
                Dobject obj_array=arglist[1].object;
                if ( (obj_array !is null) && (obj_array.isDarray()) ) {
                    propertyList = cast(Darray)obj_array;
                }
            }
        }
        // Spacer agument
        if ( arglist.length >= 3 ) {
            ushort gap_size;
            with(vtype_t) switch (arglist[2].vtype) {
                case V_NUMBER:
                    gap_size=arglist[2].toUint16;
                    break;
                case V_STRING:
                    gap=arglist[2].toText;
                    break;
                case V_OBJECT:
                    Dobject obj=arglist[2].toObject();
                    if (obj.isClass(TEXT_Number)) {
                        gap_size=obj.value.toUint16;
                    } else if (obj.isClass(TEXT_String)) {
                        gap=obj.value.toText;
                    }
                    break;
                default:
                    /* empty */
                }
            // According to ECMA standard gap size is max 10
            for(ushort i=0; (i<gap_size) && (i<10); i++) gap~=" ";
            if (gap.length > 10) gap.length=10;
        }
        recursion=Dobject.newRecursion;
        return stringify(buf,&arglist[0],gap);
    } else {
        writeln("JSON.strigify need at least one parameter\n");
    }
    ret.putVstring(buf);
    return null;
}
