import std.stdio;
import std.getopt;
import std.array;
import std.path;
import std.process;


size_t filesLength = 0;
auto files = appender!(string[])();

void addFile(string file) {
  foreach(existingFile; files.data) {
    if(file == existingFile) {
      debug writefln("[DEBUG] file '%s' already added", file);
      return;
    }
  }
  debug writefln("[DEBUG] added file '%s'", file);
  files.put(file);
  filesLength += 1 + file.length;
}


void copy(char[] dst, ref size_t offset, const(char)[] src) {
  dst[offset..offset+src.length] = src;
  offset += src.length;
}


int main(string[] args) {

  version(windows) {
    enum executableName = "performance.exe";
  } else {
    enum executableName = "performance";
  }

  //
  // Process options
  //
  bool includeSdlTests = true;

  
  //
  // options
  //
  string flags;

  flags ~= " -of"~executableName;
  flags ~= " -O";
  flags ~= " -noboundscheck";
  flags ~= " -inline";

  //
  // Add the main file
  //
  addFile("performance.d");

  if(includeSdlTests) {
    enum sdlangPath = `..\..\SDLang-D\src\sdlang_`;
    flags ~= " -version=sdl";
    addFile("common.d");
    addFile("sdl.d");
    addFile("utf8.d");
    addFile(buildPath(sdlangPath, "ast.d"));
    addFile(buildPath(sdlangPath, "exception.d"));
    addFile(buildPath(sdlangPath, "lexer.d"));
    addFile(buildPath(sdlangPath, "parser.d"));
    addFile(buildPath(sdlangPath, "symbol.d"));
    addFile(buildPath(sdlangPath, "token.d"));
    addFile(buildPath(sdlangPath, "util.d"));
  }


  
  
  //
  // Build the tests
  //
  enum compiler = "dmd";
  char[] buildCommand = new char
    [compiler.length +
     flags.length +
     filesLength];
  {
    size_t off = 0;

    copy(buildCommand, off, compiler);
    copy(buildCommand, off, flags);

    foreach(file; files.data) {
      buildCommand[off++] = ' ';
      copy(buildCommand, off, file);
    }

    assert(buildCommand.length == off);
  }

  writeln(buildCommand);
  stdout.flush();
  auto output = executeShell(buildCommand);
  if(output.status) {
    writeln("-----build output-----");
    writeln(output.output);
    writeln("-----end of build output-----");
    writeln();
    writefln("FAIL: build failed");
    return 1;
  }


  //
  // Execute the tests
  //
  writeln();
  writefln("executing '%s'", executableName);
  stdout.flush();
  auto pid = spawnShell(executableName);
  wait(pid);

  return 0;
}