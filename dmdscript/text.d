/* Digital Mars DMDScript source code.
 * Copyright (c) 2000-2002 by Chromium Communications
 * D version Copyright (c) 2004-2010 by Digital Mars
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 * written by Walter Bright
 * http://www.digitalmars.com
*
 * Upgrading to EcmaScript 5.1 by Carsten Bleser Rasmussen
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */


module dmdscript.text;


immutable(wchar[]) TEXT_ = "";
immutable(wchar[]) TEXT_source = "source";
immutable(wchar[]) TEXT_global = "global";
immutable(wchar[]) TEXT_ignoreCase = "ignoreCase";
immutable(wchar[]) TEXT_multiline = "multiline";
immutable(wchar[]) TEXT_lastIndex = "lastIndex";
immutable(wchar[]) TEXT_input = "input";
immutable(wchar[]) TEXT_lastMatch = "lastMatch";
immutable(wchar[]) TEXT_lastParen = "lastParen";
immutable(wchar[]) TEXT_leftContext = "leftContext";
immutable(wchar[]) TEXT_rightContext = "rightContext";
immutable(wchar[]) TEXT_prototype = "prototype";
immutable(wchar[]) TEXT_constructor = "constructor";
immutable(wchar[]) TEXT_toString = "toString";
immutable(wchar[]) TEXT_toLocaleString = "toLocaleString";
immutable(wchar[]) TEXT_toSource = "toSource";
immutable(wchar[]) TEXT_valueOf = "valueOf";
immutable(wchar[]) TEXT_message = "message";
immutable(wchar[]) TEXT_description = "description";
immutable(wchar[]) TEXT_Error = "Error";
immutable(wchar[]) TEXT_name = "name";
immutable(wchar[]) TEXT_length = "length";
immutable(wchar[]) TEXT_NaN = "NaN";
immutable(wchar[]) TEXT_Infinity = "Infinity";
immutable(wchar[]) TEXT_negInfinity = "-Infinity";
immutable(wchar[]) TEXT_bobjectb = "[object]";
immutable(wchar[]) TEXT_undefined = "undefined";
immutable(wchar[]) TEXT_Undefined = "Undefined";
immutable(wchar[]) TEXT_null = "null";
immutable(wchar[]) TEXT_Null = "Null";
immutable(wchar[]) TEXT_true = "true";
immutable(wchar[]) TEXT_false = "false";
immutable(wchar[]) TEXT_object = "object";
immutable(wchar[]) TEXT_string = "string";
immutable(wchar[]) TEXT_number = "number";
immutable(wchar[]) TEXT_boolean = "boolean";
immutable(wchar[]) TEXT_Object = "Object";
immutable(wchar[]) TEXT_String = "String";
immutable(wchar[]) TEXT_Number = "Number";
immutable(wchar[]) TEXT_Boolean = "Boolean";
immutable(wchar[]) TEXT_Date = "Date";
immutable(wchar[]) TEXT_Array = "Array";
immutable(wchar[]) TEXT_RegExp = "RegExp";
immutable(wchar[]) TEXT_arity = "arity";
immutable(wchar[]) TEXT_arguments = "arguments";
immutable(wchar[]) TEXT_callee = "callee";
immutable(wchar[]) TEXT_caller = "caller";                  // extension
immutable(wchar[]) TEXT_EvalError = "EvalError";
immutable(wchar[]) TEXT_RangeError = "RangeError";
immutable(wchar[]) TEXT_ReferenceError = "ReferenceError";
immutable(wchar[]) TEXT_SyntaxError = "SyntaxError";
immutable(wchar[]) TEXT_TypeError = "TypeError";
immutable(wchar[]) TEXT_URIError = "URIError";
immutable(wchar[]) TEXT_this = "this";
immutable(wchar[]) TEXT_fromCharCode = "fromCharCode";
immutable(wchar[]) TEXT_charAt = "charAt";
immutable(wchar[]) TEXT_charCodeAt = "charCodeAt";
immutable(wchar[]) TEXT_concat = "concat";
immutable(wchar[]) TEXT_indexOf = "indexOf";
immutable(wchar[]) TEXT_lastIndexOf = "lastIndexOf";
immutable(wchar[]) TEXT_localeCompare = "localeCompare";
immutable(wchar[]) TEXT_match = "match";
immutable(wchar[]) TEXT_replace = "replace";
immutable(wchar[]) TEXT_search = "search";
immutable(wchar[]) TEXT_slice = "slice";
immutable(wchar[]) TEXT_split = "split";
immutable(wchar[]) TEXT_substr = "substr";
immutable(wchar[]) TEXT_substring = "substring";
immutable(wchar[]) TEXT_toLowerCase = "toLowerCase";
immutable(wchar[]) TEXT_toLocaleLowerCase = "toLocaleLowerCase";
immutable(wchar[]) TEXT_toUpperCase = "toUpperCase";
immutable(wchar[]) TEXT_toLocaleUpperCase = "toLocaleUpperCase";
immutable(wchar[]) TEXT_hasOwnProperty = "hasOwnProperty";
immutable(wchar[]) TEXT_isPrototypeOf = "isPrototypeOf";
immutable(wchar[]) TEXT_getPrototypeOf = "getPrototypeOf";
immutable(wchar[]) TEXT_propertyIsEnumerable = "propertyIsEnumerable";
immutable(wchar[]) TEXT_dollar1 = "$1";
immutable(wchar[]) TEXT_dollar2 = "$2";
immutable(wchar[]) TEXT_dollar3 = "$3";
immutable(wchar[]) TEXT_dollar4 = "$4";
immutable(wchar[]) TEXT_dollar5 = "$5";
immutable(wchar[]) TEXT_dollar6 = "$6";
immutable(wchar[]) TEXT_dollar7 = "$7";
immutable(wchar[]) TEXT_dollar8 = "$8";
immutable(wchar[]) TEXT_dollar9 = "$9";
immutable(wchar[]) TEXT_index = "index";
immutable(wchar[]) TEXT_compile = "compile";
immutable(wchar[]) TEXT_test = "test";
immutable(wchar[]) TEXT_exec = "exec";
immutable(wchar[]) TEXT_MAX_VALUE = "MAX_VALUE";
immutable(wchar[]) TEXT_MIN_VALUE = "MIN_VALUE";
immutable(wchar[]) TEXT_NEGATIVE_INFINITY = "NEGATIVE_INFINITY";
immutable(wchar[]) TEXT_POSITIVE_INFINITY = "POSITIVE_INFINITY";
immutable(wchar[]) TEXT_dash = "-";
immutable(wchar[]) TEXT_toFixed = "toFixed";
immutable(wchar[]) TEXT_toExponential = "toExponential";
immutable(wchar[]) TEXT_toPrecision = "toPrecision";
immutable(wchar[]) TEXT_abs = "abs";
immutable(wchar[]) TEXT_acos = "acos";
immutable(wchar[]) TEXT_asin = "asin";
immutable(wchar[]) TEXT_atan = "atan";
immutable(wchar[]) TEXT_atan2 = "atan2";
immutable(wchar[]) TEXT_ceil = "ceil";
immutable(wchar[]) TEXT_cos = "cos";
immutable(wchar[]) TEXT_exp = "exp";
immutable(wchar[]) TEXT_floor = "floor";
immutable(wchar[]) TEXT_log = "log";
immutable(wchar[]) TEXT_max = "max";
immutable(wchar[]) TEXT_min = "min";
immutable(wchar[]) TEXT_pow = "pow";
immutable(wchar[]) TEXT_random = "random";
immutable(wchar[]) TEXT_round = "round";
immutable(wchar[]) TEXT_sin = "sin";
immutable(wchar[]) TEXT_sqrt = "sqrt";
immutable(wchar[]) TEXT_tan = "tan";
immutable(wchar[]) TEXT_E = "E";
immutable(wchar[]) TEXT_LN10 = "LN10";
immutable(wchar[]) TEXT_LN2 = "LN2";
immutable(wchar[]) TEXT_LOG2E = "LOG2E";
immutable(wchar[]) TEXT_LOG10E = "LOG10E";
immutable(wchar[]) TEXT_PI = "PI";
immutable(wchar[]) TEXT_SQRT1_2 = "SQRT1_2";
immutable(wchar[]) TEXT_SQRT2 = "SQRT2";
immutable(wchar[]) TEXT_parse = "parse";
immutable(wchar[]) TEXT_UTC = "UTC";

immutable(wchar[]) TEXT_getTime = "getTime";
immutable(wchar[]) TEXT_getYear = "getYear";
immutable(wchar[]) TEXT_getFullYear = "getFullYear";
immutable(wchar[]) TEXT_getUTCFullYear = "getUTCFullYear";
immutable(wchar[]) TEXT_getDate = "getDate";
immutable(wchar[]) TEXT_getUTCDate = "getUTCDate";
immutable(wchar[]) TEXT_getMonth = "getMonth";
immutable(wchar[]) TEXT_getUTCMonth = "getUTCMonth";
immutable(wchar[]) TEXT_getDay = "getDay";
immutable(wchar[]) TEXT_getUTCDay = "getUTCDay";
immutable(wchar[]) TEXT_getHours = "getHours";
immutable(wchar[]) TEXT_getUTCHours = "getUTCHours";
immutable(wchar[]) TEXT_getMinutes = "getMinutes";
immutable(wchar[]) TEXT_getUTCMinutes = "getUTCMinutes";
immutable(wchar[]) TEXT_getSeconds = "getSeconds";
immutable(wchar[]) TEXT_getUTCSeconds = "getUTCSeconds";
immutable(wchar[]) TEXT_getMilliseconds = "getMilliseconds";
immutable(wchar[]) TEXT_getUTCMilliseconds = "getUTCMilliseconds";
immutable(wchar[]) TEXT_getTimezoneOffset = "getTimezoneOffset";
immutable(wchar[]) TEXT_getVarDate = "getVarDate";

immutable(wchar[]) TEXT_setTime = "setTime";
immutable(wchar[]) TEXT_setYear = "setYear";
immutable(wchar[]) TEXT_setFullYear = "setFullYear";
immutable(wchar[]) TEXT_setUTCFullYear = "setUTCFullYear";
immutable(wchar[]) TEXT_setDate = "setDate";
immutable(wchar[]) TEXT_setUTCDate = "setUTCDate";
immutable(wchar[]) TEXT_setMonth = "setMonth";
immutable(wchar[]) TEXT_setUTCMonth = "setUTCMonth";
immutable(wchar[]) TEXT_setDay = "setDay";
immutable(wchar[]) TEXT_setUTCDay = "setUTCDay";
immutable(wchar[]) TEXT_setHours = "setHours";
immutable(wchar[]) TEXT_setUTCHours = "setUTCHours";
immutable(wchar[]) TEXT_setMinutes = "setMinutes";
immutable(wchar[]) TEXT_setUTCMinutes = "setUTCMinutes";
immutable(wchar[]) TEXT_setSeconds = "setSeconds";
immutable(wchar[]) TEXT_setUTCSeconds = "setUTCSeconds";
immutable(wchar[]) TEXT_setMilliseconds = "setMilliseconds";
immutable(wchar[]) TEXT_setUTCMilliseconds = "setUTCMilliseconds";

immutable(wchar[]) TEXT_toDateString = "toDateString";
immutable(wchar[]) TEXT_toTimeString = "toTimeString";
immutable(wchar[]) TEXT_toLocaleDateString = "toLocaleDateString";
immutable(wchar[]) TEXT_toLocaleTimeString = "toLocaleTimeString";
immutable(wchar[]) TEXT_toUTCString = "toUTCString";
immutable(wchar[]) TEXT_toGMTString = "toGMTString";

immutable(wchar[]) TEXT_comma = ",";
immutable(wchar[]) TEXT_join = "join";
immutable(wchar[]) TEXT_pop = "pop";
immutable(wchar[]) TEXT_push = "push";
immutable(wchar[]) TEXT_reverse = "reverse";
immutable(wchar[]) TEXT_shift = "shift";
immutable(wchar[]) TEXT_sort = "sort";
immutable(wchar[]) TEXT_splice = "splice";
immutable(wchar[]) TEXT_unshift = "unshift";
immutable(wchar[]) TEXT_apply = "apply";
immutable(wchar[]) TEXT_call = "call";
immutable(wchar[]) TEXT_bind = "bind";
immutable(wchar[]) TEXT_function = "function";

immutable(wchar[]) TEXT_eval = "eval";
immutable(wchar[]) TEXT_parseInt = "parseInt";
immutable(wchar[]) TEXT_parseFloat = "parseFloat";
immutable(wchar[]) TEXT_escape = "escape";
immutable(wchar[]) TEXT_unescape = "unescape";
immutable(wchar[]) TEXT_isNaN = "isNaN";
immutable(wchar[]) TEXT_isFinite = "isFinite";
immutable(wchar[]) TEXT_decodeURI = "decodeURI";
immutable(wchar[]) TEXT_decodeURIComponent = "decodeURIComponent";
immutable(wchar[]) TEXT_encodeURI = "encodeURI";
immutable(wchar[]) TEXT_encodeURIComponent = "encodeURIComponent";

immutable(wchar[]) TEXT_print = "print";
immutable(wchar[]) TEXT_println = "println";
immutable(wchar[]) TEXT_readln = "readln";
immutable(wchar[]) TEXT_getenv = "getenv";
immutable(wchar[]) TEXT_assert = "assert";

immutable(wchar[]) TEXT_Function = "Function";
immutable(wchar[]) TEXT_Math = "Math";

immutable(wchar[]) TEXT_0 = "0";
immutable(wchar[]) TEXT_1 = "1";
immutable(wchar[]) TEXT_2 = "2";
immutable(wchar[]) TEXT_3 = "3";
immutable(wchar[]) TEXT_4 = "4";
immutable(wchar[]) TEXT_5 = "5";
immutable(wchar[]) TEXT_6 = "6";
immutable(wchar[]) TEXT_7 = "7";
immutable(wchar[]) TEXT_8 = "8";
immutable(wchar[]) TEXT_9 = "9";

immutable(wchar[]) TEXT_anchor = "anchor";
immutable(wchar[]) TEXT_big = "big";
immutable(wchar[]) TEXT_blink = "blink";
immutable(wchar[]) TEXT_bold = "bold";
immutable(wchar[]) TEXT_fixed = "fixed";
immutable(wchar[]) TEXT_fontcolor = "fontcolor";
immutable(wchar[]) TEXT_fontsize = "fontsize";
immutable(wchar[]) TEXT_italics = "italics";
immutable(wchar[]) TEXT_link = "link";
immutable(wchar[]) TEXT_small = "small";
immutable(wchar[]) TEXT_strike = "strike";
immutable(wchar[]) TEXT_sub = "sub";
immutable(wchar[]) TEXT_sup = "sup";

immutable(wchar[]) TEXT_Enumerator = "Enumerator";
immutable(wchar[]) TEXT_item = "item";
immutable(wchar[]) TEXT_atEnd = "atEnd";
immutable(wchar[]) TEXT_moveNext = "moveNext";
immutable(wchar[]) TEXT_moveFirst = "moveFirst";

immutable(wchar[]) TEXT_VBArray = "VBArray";
immutable(wchar[]) TEXT_dimensions = "dimensions";
immutable(wchar[]) TEXT_getItem = "getItem";
immutable(wchar[]) TEXT_lbound = "lbound";
immutable(wchar[]) TEXT_toArray = "toArray";
immutable(wchar[]) TEXT_ubound = "ubound";

immutable(wchar[]) TEXT_ScriptEngine = "ScriptEngine";
immutable(wchar[]) TEXT_ScriptEngineBuildVersion = "ScriptEngineBuildVersion";
immutable(wchar[]) TEXT_ScriptEngineMajorVersion = "ScriptEngineMajorVersion";
immutable(wchar[]) TEXT_ScriptEngineMinorVersion = "ScriptEngineMinorVersion";
immutable(wchar[]) TEXT_DMDScript = "DMDScript";

immutable(wchar[]) TEXT_date = "date";
immutable(wchar[]) TEXT_unknown = "unknown";

version(Ecmascript5) {
immutable(wchar[]) TEXT_JSON      = "JSON";
immutable(wchar[]) TEXT_stringify = "stringify";
immutable(wchar[]) TEXT_use_strict = "use strict";
}
immutable(wchar[]) TEXT_use_trace = "use trace";

// Debug info
immutable(wchar[]) TEXT_eval_verbose = "eval_verbose";
// Array property function added
immutable(wchar[]) TEXT_forEach      = "forEach";
immutable(wchar[]) TEXT_reduce       = "reduce";
// Array static function
immutable(wchar[]) TEXT_isArray      = "isArray";
// Object static functions
immutable(wchar[]) TEXT_keys         = "keys";
immutable(wchar[]) TEXT_getOwnPropertyNames = "getOwnPropertyNames";
immutable(wchar[]) TEXT_getOwnPropertyDescriptor = "getOwnPropertyDescriptor";
immutable(wchar[]) TEXT_defineProperty           = "defineProperty";
immutable(wchar[]) TEXT_defineProperties         = "defineProperties";
immutable(wchar[]) TEXT_create                   = "create";
immutable(wchar[]) TEXT_preventExtensions        = "preventExtensions";
immutable(wchar[]) TEXT_seal                     = "seal";
immutable(wchar[]) TEXT_freeze                   = "freeze";
immutable(wchar[]) TEXT_isExtensible             = "isExtensible";
immutable(wchar[]) TEXT_isSealed                 = "isSealed";
immutable(wchar[]) TEXT_isFrozen                 = "isForzen";


// Property descriptions
immutable(wchar[]) TEXT_value        = "value";
immutable(wchar[]) TEXT_writable     = "writable";
immutable(wchar[]) TEXT_enumerable   = "enumerable";
immutable(wchar[]) TEXT_configurable = "configurable";
immutable(wchar[]) TEXT_set          = "set";
immutable(wchar[]) TEXT_get          = "get";


// Console
immutable(wchar[]) TEXT_Console      = "console";
//immutable(wchar[]) TEXT_log          = "log";

immutable(wchar[]) TEXT_isStrictMode = "isStrictMode";
