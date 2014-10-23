import std.stdio;
import std.file;
import std.getopt;
import std.array;
import std.path;
import std.process;
import std.datetime;

import more.common;

auto sourceFiles = appender!(SourceFile[])();
struct SourceFile
{
  string filename;
  bool debug_;
  bool unittest_;

  SourceFile combine(SourceFile *other)
  {
    return SourceFile(filename,
		      debug_ || other.debug_,
		      unittest_ || unittest_);
  }
}

void addFile(string filename, bool debug_, bool unittest_) {
  foreach(i, existingFile; sourceFiles.data) {
    if(filename == existingFile.filename) {
      sourceFiles.data[i] = SourceFile(filename,
				 debug_ || existingFile.debug_,
				 unittest_ || existingFile.unittest_);
      return;
    }
  }
  debug writefln("[DEBUG] added file '%s'", filename);
  sourceFiles.put(SourceFile(filename, debug_, unittest_));
}


bool exec(const(char[]) command)
{
  writefln("%s", command);
  stdout.flush();
  long before = Clock.currStdTime();
  auto output = executeShell(command);
  if(output.status) {
    writefln("FAILED: %s", command);
    writeln("-----failed output-----------");
    writeln(output.output);
    writeln("-----end of output-----------");
    writeln();
    writefln("FAILED");
    return false;
  }
  write(output.output);

  
  write("");
  foreach(i; 0..command.length+ 2) write(' ');
  writeln(prettyTime(stdTimeMillis(Clock.currStdTime() - before)));
  stdout.flush();
  return true;
}
void spawn(const(char[]) command)
{
  writefln("%s", command);
  stdout.flush();
  long before = Clock.currStdTime();
  auto pid = spawnShell(command);
  wait(pid);
  foreach(i; 0..command.length+ 2) write(' ');
  writeln(prettyTime(stdTimeMillis(Clock.currStdTime() - before)));
  stdout.flush();
}

void copy(char[] dst, ref size_t offset, const(char)[] src) {
  dst[offset..offset+src.length] = src;
  offset += src.length;
}

void usage() {
  writeln("test [options...] modules...");
  writeln("    modules all, common, utf8, sdl, sdlreflection, sos");
  writeln(" options:");
  writeln("    --D       generate docs");
  writeln("    --debug   compile as debug");
  writeln("    --cov     compile with -cov flag");
  writeln("    --notest  skip the unit tests");
}
int main(string[] args) {
  bool generateDoc;
  bool debug_;
  bool cov;
  bool notest;

  // Add more options
  // DDox JSON -D -X -Xfdocs.json

  getopt(args,
	 "D", &generateDoc,
	 "debug", &debug_,
	 "cov", &cov,
	 "notest", &notest);

  bool unittest_ = !notest;

  if(args.length <= 1) {
    usage();
    return 1;
  }

  version(windows) {
    enum executableName = "unittest.exe";
  } else {
    enum executableName = "unittest";
  }


  foreach(arg; args[1..$]) {
    string module_ = arg;
    if(module_ == "all") {

      addFile("common.d"       , debug_, true);
      addFile("utf8.d"         , debug_, true);
      addFile("sdl.d"          , debug_, true);
      addFile("sdlreflection.d", debug_, true);
      addFile("sos.d"          , debug_, true);

    } else if(module_ == "common") {

      addFile("common.d"       , debug_, true);

    } else if(module_ == "utf8") {

      addFile("common.d"       , false, false);
      addFile("utf8.d"       , debug_, true);

    } else if(module_ == "fields") {

      addFile("common.d"       , false, false);
      addFile("utf8.d"         , false, false);
      addFile("fields.d"       , debug_, true);

      /*
    } else if(module_ == "ason") {

      addFile("common.d"       , false, false);
      addFile("utf8.d"         , false, false);
      addFile("ason.d"         , debug_, true);
      */
    } else if(module_ == "sdl") {

      addFile("common.d"       , false, false);
      addFile("utf8.d"         , false, false);
      addFile("sdl.d"          , debug_, true);

    } else if(module_ == "sdl2") {

      addFile("common.d"       , false, false);
      addFile("utf8.d"         , false, false);
      addFile("sdl2.d"         , debug_, true);

    } else if(module_ == "sdlreflection") {

      addFile("common.d"       , false, false);
      addFile("utf8.d"         , false, false);
      addFile("sdl.d"          , false, false);
      addFile("sdlreflection.d", debug_, true);

    } else if(module_ == "sos") {

      addFile("common.d"       , false, false);
      addFile("sos.d", debug_, true);

    } else {
      writefln("Error: unknown module '%s'", module_);
      return 1;
    }
  }

  enum compiler = "dmd";
  auto buildCommand = appender!(char[])();
  
  //
  // options
  //
  buildCommand.clear();
  buildCommand.put(compiler);

  buildCommand.put(" -I..");

  buildCommand.put(" -of");
  buildCommand.put(executableName);

  buildCommand.put(" -main");

  if(unittest_)
    buildCommand.put(" -unittest");

  if(debug_)
    buildCommand.put(" -debug");

  if(generateDoc) {
    //buildCommand.put(" -D");
    buildCommand.put(" -D -X -Xfdocs.json");
  }

  if(cov)
    buildCommand.put(" -cov");

  //flags ~= " -O";
  //flags ~= " -noboundscheck";
  //flags ~= " -inline";

  foreach(source; sourceFiles.data) {
    if(unittest_ && source.unittest_) {
      buildCommand.put(" -version=unittest_");
      buildCommand.put(stripExtension(source.filename));
    }

    buildCommand.put(' ');
    buildCommand.put(source.filename);
  }

  if(!exec(buildCommand.data)) return 1;
  
  if(unittest_)
    spawn("unittest.exe");

  return 0;
}
