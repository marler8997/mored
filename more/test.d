module more.test;

import std.stdio : writeln, writefln;
import std.format : format;

__gshared uint passTestCount;
__gshared uint failTestCount;

enum outerBar = "=========================================";
enum innerBar = "-----------------------------------------";
void startTest(string name)
{
    version (PrintTestBoundaries)
    {
        writeln(outerBar);
        writeln(name, ": Start");
        writeln(innerBar);
    }
}
void endFailedTest(string name)
{
    failTestCount++;
    version (PrintTestBoundaries)
    {
        writeln(innerBar);
        writeln(name, ": Failed");
        writeln(outerBar);
    }
}
void endPassedTest(string name)
{
    passTestCount++;
    version (PrintTestBoundaries)
    {
        writeln(innerBar);
        writeln(name, ": Passed");
        writeln(outerBar);
    }
}
template scopedTest(string name) {
    enum scopedTest =
      "startTest(\""~name~"\");"~
      "scope(failure) {import std.stdio : stdout; stdout.flush();endFailedTest(\""~name~"\");}"~
      "scope(success) endPassedTest(\""~name~"\");";
}
void writeSection(string name)
{
    writeln(innerBar);
    writeln(name);
    writeln(innerBar);
}
void assertEqual(string expected, string actual) pure
{
    if(expected != actual) {
      throw new Exception(format("Expected %s Actual %s",
          expected ? ('"' ~ expected ~ '"') : "<null>",
          actual   ? ('"' ~ actual   ~ '"') : "<null>"));
    }
}
void dumpTestResults()
{
    writeSection("Final Results");
    writefln("%s test(s) passed", passTestCount);
    writefln("%s test(s) failed", failTestCount);
}
