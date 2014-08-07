import std.stdio;
import std.conv;
import std.string;
import std.traits;
import std.datetime;

///
/// Challenge: Write code that will call any function pointer/delegate given an array of strings
/// Note:  You must also return the return value of the function pointer.
///


/// Calls the given function pointer or delgate with the given string
/// arguments parsed to the appropriate argument types.
ReturnType!Function call(Function)(Function func, const char[][] args...) if (isCallable!Function)
{
  alias Args = ParameterTypeTuple!Function;

  if(args.length != Args.length)
    throw new Exception(format("Expected %d arguments but got %d", Args.length, args.length));

  Args argsTuple;

  foreach(i,Arg;Args) {
    argsTuple[i] = to!Arg(args[i]);
  }

  return func(argsTuple);
}

unittest
{
  void voidFunction()
  {
    writeln("[Test] Called voidFunction()");
  }
  void randomFunction(int i, uint u, string s, char c)
  {
    writefln("[Test] Called randomFunction(%s, %s, \"%s\", '%s')", i, u, s, c);
  }
  ulong echoUlong(ulong value)
  {
    writefln("[Test] Called echoUlong(%s)", value);
    return value;
  }

 (&voidFunction).call();
 (&randomFunction).call("-1000", "567", "HelloWorld!", "?");

  string passedValue = "123456789";
  ulong returnValue = (&echoUlong).call(passedValue);
  writefln("[Test] echoUlong(%s) = %s", passedValue, returnValue);

  try {
    (&randomFunction).call("wrong number of args");
    assert(0);
  } catch(Exception e) {
    writefln("[Test] Caught %s: '%s'", typeid(e), e.msg);
  }

  writeln("[Test] Success");




  //
  // Performance Test
  //
  enum LOOP_COUNT = 1000000;

  void fourArgFunction(int i, uint u, string s, char c) { }
  writefln("[PerformanceTest] Calling 4 parameter function %s times...", LOOP_COUNT);

  auto startTime = Clock.currTime();
  for(int i = 0; i < LOOP_COUNT; i++) {
    int first = to!int("-1000");
    uint second = to!uint("567");
    string third = to!string("HelloWorld!");
    char fourth = to!char("?");
    fourArgFunction(first, second, third, fourth);
  }
  auto endTime = Clock.currTime();

  writefln("[PerformanceTest] Calling function directly: %s", (endTime - startTime));

  startTime = Clock.currTime();
  for(int i = 0; i < LOOP_COUNT; i++) {
    (&fourArgFunction).call("-1000", "567", "HelloWorld!", "?");
  }
  endTime = Clock.currTime();

  writefln("[PerformanceTest] Using Call Function      : %s", (endTime - startTime));


}