import std.stdio;
import std.datetime;

import more.utf8;


version(sdl) {
  // SDL TESTS
  import sdlang_.ast;
  import sdlang_.parser;
  import more.sdl;
}



bool printIndividualTestRuns = true;

void notifyStart(string name)
{
  writefln("--------------------------------------");
  writefln("Performance Test: '%s'", name);
  writefln("--------------------------------------");
  stdout.flush();
}

void logTime(uint run, string id, float time)
{
  writefln("run %s: %-24s : %f millis", run, id, time);
}

float stdTimeMillis(long stdTime)
{
  return cast(float)stdTime / 10000f;
}

void TestRun(tests...)(string name, uint runs, uint iterations)
{
  float[tests.length] times = 0;

  notifyStart(name);

  foreach(run; 0..runs) {

    foreach(testIndex, test; tests) {
      static if(testIndex % 2 == 1) {

	long before = Clock.currStdTime();
	foreach(iteration; 0..iterations) {
	  mixin(test);
	}
	float runTime = stdTimeMillis(Clock.currStdTime() - before);
	if(printIndividualTestRuns) {
	  logTime(run, tests[testIndex-1] , runTime);
	}
	times[testIndex / 2] += runTime;
      }
    }

  }

  foreach(testIndex, test; tests) {
    static if(testIndex % 2 == 0) {
      writefln("%-24s : %f millis", test, times[testIndex/2]);
    }
  }
  stdout.flush();
}


string testStringA = "abcdefg";


struct ABCStruct {
  int a, b, c;
}
ABCStruct abcStruct;
struct ABCStructConstructor {
  int a, b, c;
  this(int a, int b, int c) {
    this.a = a;
    this.b = b;
    this.c = c;
  }
}


version(sdl) {

  string testSdlString = `
first-tag "value" "another-value" myattribute=null {
    child-tag name="freddy" {
        grand-child-tag name="jimmy" {
        }
    }
}
second-tag "cool" iscool=true {

}
a-list "apple" null true false on off
a-matrix {
 1 2 3 4 5
 3 4 5 6 7
}

`;

}

void ModifyByReference(ref ABCStruct s) {
  s.a = 1;
  s.b = 1;
  s.c = 1;
}
void ModifyByPointer(ABCStruct *s) {
  s.a = 1;
  s.b = 1;
  s.c = 1;
}
ABCStruct *ModifyByPointerAndReturn(ABCStruct *s) {
  s.a = 1;
  s.b = 1;
  s.c = 1;
  return s;
}

void main(string[] args)
{
  int i, iterations;
  uint run;
  long before;

  void start() {
    before = Clock.currStdTime();
  }
  void end(string id) {
    logTime(run, id, stdTimeMillis(Clock.currStdTime() - before));
  }


  enum runCount = 2;

  TestRun!(
	   "Clock.currStdTime()"   , "long time = Clock.currStdTime();",
	   "Clock.currSystemTick()", "TickDuration d = Clock.currSystemTick();",
	   "Clock.currAppTick()"   , "TickDuration d = Clock.currAppTick();",
	   "Clock.currTime()"      , "SysTime time = Clock.currTime();"
	   )("FastestClockFunction", runCount, 1000000);

  TestRun!(
	   "StructInitializer"   , "ABCStruct s = {a:1,b:2,c:3};",
	   "StructConstructor"   , "ABCStructConstructor s = ABCStructConstructor(1,2,3);"
	   )("Struct Initializer vs Constructor", runCount, 10000000);

  TestRun!(
	   "StructReference"       , "ModifyByReference(abcStruct);",
	   "StructPointer"         , "ModifyByPointer(&abcStruct);",
	   "StructPointerAndReturn", "ModifyByPointerAndReturn(&abcStruct);"
	   )("Struct ref vs pointer", runCount, 10000000);

  TestRun!(
	   "ArrayLoopOffset"       , "string str = testStringA; size_t off = 0; while(true) { if(off >= str.length) break; off++; }",
	   "ArrayLoopSlice"        , "string str = testStringA;while(true) { if(str.length <= 0) break; str = str[1..$];}"
	   )("Array Offset vs Slice", runCount, 10000000);

  TestRun!(
	   "MarlerUtf8Decode"       , "string str = testStringA; auto start = str.ptr; decodeUtf8(start, str.ptr + str.length);",
	   "BjoernUtf8Decode"       , "string str = testStringA; auto start = str.ptr; bjoernDecodeUtf8(start, str.ptr + str.length);"
	   )("Marler vs Bjoern Utf8 Decode", runCount, 1000000);


  version(sdl) {

    TestRun!(
	     "sdlang_"         , "sdlang_.ast.Tag tag; tag = sdlang_.parser.parseSource(testSdlString);",
	     "more.sdl"        , "more.sdl.Tag tag; char[] sdl = cast(char[])testSdlString; while(more.sdl.parseSdlTag(&tag, &sdl)) { }"
	     )("sdlang_ vs more.sdl", runCount, 10000);

  }
}
