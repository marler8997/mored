import std.stdio;
import std.format : format;
import std.string : indexOf;
import std.file;
import std.getopt;
import std.array;
import std.path;
import std.traits : EnumMembers;
import std.process;
import std.datetime;

import more.common;
import more.types;
import moduledeps;


enum ModuleState
{
    exclude    = 0,
    include   = 1,
    unittest_  = 2,
}
__gshared ModuleState[EnumMembers!M.length] moduleStateTable;
@property ModuleState state(M mod) { return moduleStateTable[cast(ushort)mod]; }

void includeModule(M mod)
{
    final switch(mod.state)
    {
        case ModuleState.exclude:
            // important to set this before adding deps to prevent
            // infinite recursion
            moduleStateTable[cast(ushort)mod] = ModuleState.include;
            foreach(dep; mod.normalDeps)
            {
                includeModule(dep);
            }
            break;
        case ModuleState.include:
            break;
        case ModuleState.unittest_:
            break;

    }
}
void unittestModule(M mod)
{
    final switch(mod.state)
    {
        case ModuleState.exclude:
            goto case ModuleState.include;
        case ModuleState.include:
            // important to set this before adding deps to prevent
            // infinite recursion
            moduleStateTable[cast(ushort)mod] = ModuleState.unittest_;
            foreach(dep; mod.unittestDeps)
            {
                includeModule(dep);
            }
            break;
        case ModuleState.unittest_:
            break;

    }
}

passfail exec(const(char[]) command)
{
    writefln("[SHELL] %s", command);
    stdout.flush();
    long before = Clock.currStdTime();
    auto output = executeShell(command);
    if(output.output.length > 0)
    {
        writeln("-------------------------------------------------");
        write(output.output);
        if(output.output.length == 0 || output.output[$-1] != '\n')
        {
            writeln();
        }
        writeln("-------------------------------------------------");
    }
    if(output.status)
    {
        writefln("SHELL COMMAND FAILED(exitcode=%s): %s", output.status, command);
        return passfail.fail;
    }
    writeln(prettyTime(stdTimeMillis(Clock.currStdTime() - before)));
    stdout.flush();
    return passfail.pass;
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

void copy(char[] dst, ref size_t offset, const(char)[] src)
{
    dst[offset..offset+src.length] = src;
    offset += src.length;
}

//
// TODO: Rename this to something like "build.d"
// Make sub commands such as
//
//   build test ...
//   build gendoc ...
//
void usage()
{
    writeln("go gendoc");
    writeln("go test [options...] all");
    writeln("go test [options...] module1 module2...");
    write("Modules: ");
    {
        string prefix = "";
        foreach(mod; EnumMembers!M)
        {
            writef("%s%s", prefix, mod.name);
            prefix = ", ";
        }
    }
    writeln();
    writeln(" options:");
    writeln("    -debug   compile as debug");
    writeln("    -cov     compile with -cov flag");
    writeln("    -notest  skip the unit tests");
}
int main(string[] args)
{
    args = args[1..$];
    if(args.length == 0)
    {
        usage();
        return 1;
    }
    auto command = args[0];
    args = args[1..$];
    if(command == "gendoc")
    {
        return gendoc(args);
    }
    else if(command == "test")
    {
        return test(args);
    }
    else
    {
        writefln("Error: unknown command '%s'", command);
        return 1;
    }
}
int gendoc(string[] args)
{
    auto command = appender!(char[])();
    command.put("dmd -o- -D -Dddoc -X -Xfdoc/docs.json");
    foreach(mod; EnumMembers!M)
    {
        command.put(" ");
        command.put(mod.filename);
    }
    if(failed(exec(command.data)))
    {
        return 1; // fail
    }
    return 0; // success
}
int test(string[] args)
{
    bool generateDoc;
    bool debug_;
    bool cov;
    bool unittest_ = true;

    // Add more options
    // DDox JSON -D -X -Xfdocs.json
    {
        auto newArgsLength = 0;
        scope(exit) args.length = newArgsLength;
        for(size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if(arg.length > 0 && arg[0] != '-')
            {
                args[newArgsLength++] = arg;
            }
            else if(arg == "-debug")
            {
                debug_ = true;
            }
            else if(arg == "-cov")
            {
                cov = true;
            }
            else if(arg == "-notest")
            {
                unittest_ = false;
            }
            else
            {
                writefln("unknown option '%s'", arg);
                return 1;
            }
        }
    }
    if(args.length == 0)
    {
        writeln("no modules were given to test");
        return 1;
    }

    foreach(arg; args)
    {
        string module_ = arg;
        if(module_ == "all")
        {
            foreach(mod; EnumMembers!M)
            {
                moduleStateTable[cast(ushort)mod] = ModuleState.unittest_;
            }
        }
        else
        {
            bool foundMatch = false;
            foreach(mod; EnumMembers!M)
            {
                if(arg == mod.name)
                {
                    unittestModule(mod);
                    foundMatch = true;
                    break;
                }
            }
            if(!foundMatch)
            {
                writefln("Error: unknown module '%s'", module_);
                return 1;
            }
        }
    }

    //
    // Compile non-unittest modules
    // Need to compile them seperately so they don't have the "-unittest" option.
    //
    version(Windows)
    {
        enum unittestDepsOutFile = "unittest_deps.obj";
        enum unittestExe = "unittest.exe";
    }
    else
    {
        enum unittestDepsOutFile = "unittest_deps.o";
        enum unittestExe = "unittest";
    }

    bool compiledDeps = false;

    static void appendModule(T)(T builder, M mod)
    {
        builder.put(" ");
        builder.put(mod.filename);
    }

    // Make sure this test is included because it is used by testmain.d
    includeModule(M.test);

    {
        auto files = appender!(char[])();
        foreach(mod; EnumMembers!M)
        {
            final switch(mod.state)
            {
                case ModuleState.exclude:
                    break;
                case ModuleState.include:
                    appendModule(files, mod);
                    break;
                case ModuleState.unittest_:
                    break;
            }
        }
        if(files.data.length > 0)
        {
            if(failed(compile(unittestDepsOutFile, "-c", files.data)))
            {
                return 1; // fail
            }
            compiledDeps = true;
        }
    }
    //
    // Compile unittest modules
    //
    {
        auto files = appender!(char[])();

        files.put(" ");
        files.put("testmain.d");

        if(compiledDeps)
        {
            files.put(" ");
            files.put(unittestDepsOutFile);
        }
        foreach(mod; EnumMembers!M)
        {
            final switch(mod.state)
            {
                case ModuleState.exclude:
                    break;
                case ModuleState.include:
                    break;
                case ModuleState.unittest_:
                    appendModule(files, mod);
                    break;
            }
        }

        auto options = appender!(char[])();
        if(unittest_)
            options.put(" -unittest");

        if(debug_)
            options.put(" -debug");

        if(generateDoc) {
            //options.put(" -D");
            options.put(" -D -X -Xfdocs.json");
        }
        if(cov)
            options.put(" -cov");

        if(failed(compile("unittest", options.data, files.data)))
        {
            return 1; // fail
        }
    }

    if(unittest_)
    {
        version(Windows)
        {
            spawn(unittestExe);
        }
        else
        {
            spawn("./"~unittestExe);
        }
    }

    return 0;
}

passfail compile(const(char)[] outputFile, const(char)[] options, const(char)[] files)
{
    auto command = appender!(char[])();

    command.put("dmd");
    command.put(" -of");
    command.put(outputFile);
    command.put(" ");
    command.put(options);
    command.put(" ");
    command.put(files);

    return exec(command.data);
}
