import std.stdio;
import std.conv;
import std.range;
import std.traits;
import std.string;

import more.common;

template SosTypeName(T)
{
  static if(isArray!T) {
    static if(isChar!(ArrayElementType!T)) {
      immutable SosTypeName = "String";
    } else {
      immutable SosTypeName = SosTypeName!(ArrayElementType!T) ~ "[]";
    }
  } else static if(is(T == void)) {
    immutable SosTypeName = "Void";
  } else static if(is(T == bool)) {
    immutable SosTypeName = "Boolean";
  } else static if(is(T == byte)) {
    immutable SosTypeName = "SByte";
  } else static if(is(T == ubyte)) {
    immutable SosTypeName = "Byte";
  } else static if(is(T == short)) {
    immutable SosTypeName = "Int16";
  } else static if(is(T == ushort) || is(T == wchar)) {
    immutable SosTypeName = "UInt16";
  } else static if(is(T == int)) {
    immutable SosTypeName = "Int32";
  } else static if(is(T == uint) || is(T == dchar)) {
    immutable SosTypeName = "UInt32";
  } else static if(is(T == long)) {
    immutable SosTypeName = "Int64";
  } else static if(is(T == ulong)) {
    immutable SosTypeName = "UInt64";
  } else static if(is(T == float)) {
    immutable SosTypeName = "Single";
  } else static if(is(T == double)) {
    immutable SosTypeName = "Double";
  } else static if(isChar!T) {
    immutable SosTypeName = "Char";
  } else {
      //immutable SosTypeName = new Exception(format("No sysTypeName for '%s'", T.stringof));
    immutable SosTypeName = T.stringof;
  }
}
/+
template SosTypeNames(alias sep, T...)
{
  static if(T.length == 0) {
    immutable string SosTypeNames = "";
  } else static if(T.length == 1) {
    immutable string SosTypeNames = SosTypeName!(T[0]);
  } else {
    immutable string SosTypeNames = SosTypeName!(T[0]) ~ sep ~ SosTypeNames!(sep, T[1..$]);
  }
}
+/
version(unittest_sos) unittest
{
  mixin(scopedTest!("Sos Types"));

  assertEqual("Void"   , SosTypeName!void);

  assertEqual("Boolean", SosTypeName!bool);
  //assertEqual("Boolean", SosTypeName!(const bool));     (Not supported yet)
  //assertEqual("Boolean", SosTypeName!(immutable bool)); (Not supported yet)

  assertEqual("SByte"  , SosTypeName!byte);

  assertEqual("Byte"   , SosTypeName!ubyte);

  assertEqual("Int16", SosTypeName!short);
  assertEqual("UInt16", SosTypeName!ushort);
  assertEqual("UInt16", SosTypeName!wchar);

  assertEqual("Int32", SosTypeName!int);
  assertEqual("UInt32", SosTypeName!uint);
  assertEqual("UInt32", SosTypeName!dchar);

  assertEqual("Int64", SosTypeName!long);
  assertEqual("UInt64", SosTypeName!ulong);

  assertEqual("Single", SosTypeName!float);
  assertEqual("Double", SosTypeName!double);

  assertEqual("Char", SosTypeName!char);

  assertEqual("String", SosTypeName!(char[]));
  assertEqual("String", SosTypeName!(const(char)[]));
  assertEqual("String", SosTypeName!(const char[]));
  assertEqual("String", SosTypeName!(immutable(char)[]));
  assertEqual("String", SosTypeName!(immutable char[]));
  assertEqual("String", SosTypeName!string);

  // Test Array Types
  assertEqual("Boolean[]", SosTypeName!(bool[]));

  assertEqual("SByte[]"  , SosTypeName!(byte[]));

  assertEqual("Byte[]"   , SosTypeName!(ubyte[]));

  assertEqual("Int16[]", SosTypeName!(short[]));
  assertEqual("UInt16[]", SosTypeName!(ushort[]));
  assertEqual("UInt16[]", SosTypeName!(wchar[]));

  assertEqual("Int32[]", SosTypeName!(int[]));
  assertEqual("UInt32[]", SosTypeName!(uint[]));
  assertEqual("UInt32[]", SosTypeName!(dchar[]));

  assertEqual("Int64[]", SosTypeName!(long[]));
  assertEqual("UInt64[]", SosTypeName!(ulong[]));

  assertEqual("Single[]", SosTypeName!(float[]));
  assertEqual("Double[]", SosTypeName!(double[]));

  assertEqual("String[]", SosTypeName!(char[][]));
  assertEqual("String[]", SosTypeName!(const(char)[][]));
  assertEqual("String[]", SosTypeName!(const(char[])[]));
  assertEqual("String[]", SosTypeName!(const char[][]));
  assertEqual("String[]", SosTypeName!(immutable(char)[][]));
  assertEqual("String[]", SosTypeName!(immutable(char[])[]));
  assertEqual("String[]", SosTypeName!(immutable char[][]));
  assertEqual("String[]", SosTypeName!(string[]));
}
/+
template SosTypeNameStrings(T...)
{
  static if(T.length == 0) {
    immutable string SosTypeNameStrings = "";
  } else static if(T.length == 1) {
    immutable string SosTypeNameStrings = '"' ~ SosTypeName!(T[0]) ~ '"';
  } else {
    immutable string SosTypeNameStrings = '"' ~ SosTypeName!(T[0]) ~ '"' ~ ',' ~ SosTypeNameStrings!(sep, T[1..$]);
  }
}
+/
template SosTypeNameStrings(F, T...)
{
  static if(T.length == 0) {
    immutable string SosTypeNameStrings = '"' ~ SosTypeName!(F) ~ '"';
  } else {
    immutable string SosTypeNameStrings = '"' ~ SosTypeName!(F) ~ '"' ~ ',' ~ SosTypeNameStrings!(T[0], T[1..$]);
  }
}
template SosMethodTemplate(string methodName, Function)
{
  static if((ParameterTypeTuple!Function).length == 0) {
    shared auto SosMethodTemplate =
      new immutable SosMethodDefinition(methodName,
					SosTypeName!(ReturnType!Function), null);
  } else {
    shared auto SosMethodTemplate =
      new immutable SosMethodDefinition(methodName,
					SosTypeName!(ReturnType!Function),
					[mixin(SosTypeNameStrings!(ParameterTypeTuple!Function))]);
  }
}
public class SosMethodDefinition
{
  public immutable string name;
  public immutable string nameLowerCase;
  public immutable string returnSosTypeName;
  public immutable string[] parameterSosTypeNames;

  public immutable string definition;
  public immutable this(string name, string returnSosTypeName,
			immutable string[] parameterSosTypeNames)
  {
    this.name = name;
    this.nameLowerCase = name.toLower();
    this.returnSosTypeName = returnSosTypeName;
    this.parameterSosTypeNames = parameterSosTypeNames;

    string definition = returnSosTypeName ~ ' ' ~
      name ~ '(';
    foreach(i, n ; parameterSosTypeNames) {
      if(i > 0) definition ~= ",";
      definition ~= n;
    }
    definition ~= ')';
    this.definition = definition;
  }
}



version(unittest_sos) unittest
{
  mixin(scopedTest!("Sos Method Definitions"));

  void testFunction1(int a, string b)
  {
  }

  immutable SosMethodDefinition definition1 =
    SosMethodTemplate!("testFunction1", typeof(testFunction1));

  writefln("Definition = '%s'", definition1.definition);
  assertEqual("Void testFunction1(String)", definition1.definition);

}
