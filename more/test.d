module more.test;

import std.stdio : writeln;
import std.format : format;

enum outerBar = "=========================================";
enum innerBar = "-----------------------------------------";
void startTest(string name)
{
    writeln(outerBar);
    writeln(name, ": Start");
    writeln(innerBar);
}
void endFailedTest(string name)
{
    writeln(innerBar);
    writeln(name, ": Failed");
    writeln(outerBar);
}
void endPassedTest(string name)
{
    writeln(innerBar);
    writeln(name, ": Passed");
    writeln(outerBar);
}
template scopedTest(string name) {
    enum scopedTest =
      "startTest(\""~name~"\");"~
      "scope(failure) {stdout.flush();endFailedTest(\""~name~"\");}"~
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
