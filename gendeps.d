#!/usr/bin/env rund
import std.stdio : File, writeln, writefln;
import std.format : format;
import std.string : startsWith, replace, endsWith;
import std.array  : Appender;
import std.file : dirEntries, SpanMode, mkdir, exists, timeLastModified;
import std.path : dirName, buildPath, buildNormalizedPath, relativePath, baseName, stripExtension;
import std.process;
import std.typecons : Flag, Yes, No;

import more.parse : skipSpace, startsWith, findCharIndex;

auto stripPackage(string path)
{
    if (path.endsWith("package.d"))
    {
        auto temp = path[0 .. $ - "package.d".length];
        if (temp.length > 0 && (temp[$ - 1] == '/' || temp[$ - 1] == '\\'))
            return temp[0 .. $-1];
    }
    return path;
}
struct Module
{
    string filename;
    string name;
    Appender!(string[]) normalDeps;
    Appender!(string[]) unittestDeps;
    this(string filename)
    {
        this.filename = filename;
        this.name = filename[moreRoot.length + 1 ..$].stripPackage.stripExtension.replace("/", "_").replace("\\", "_");
    }
}
enum DepType
{
    normal, unittest_
}
string name(DepType type) { return type == DepType.normal ? "normal" : "unittest"; }

__gshared string moreRoot;
__gshared string objDir;

// Define custom writeln function so they always use "\n" as newline character
void outln(File file) { file.write("\n"); }
void outln(T...)(File file, string format, T args)
{
    file.writef(format, args);
    file.write("\n");
}

int main(string[] args)
{
    auto repoRootFullPath = dirName(__FILE_FULL_PATH__);
    auto repoRoot = buildNormalizedPath(relativePath(repoRootFullPath));
    moreRoot = buildPath(repoRoot, "more");
    auto outputFilename = buildPath(repoRoot, "moduledeps.d");

    args = args[1..$];
    if(args.length > 0 && args[0] == "checked")
    {
        if(exists(outputFilename))
        {
            auto gendepsFilename = buildPath(repoRoot, "gendeps.d");
            if(timeLastModified(gendepsFilename) < timeLastModified(outputFilename))
            {
                // already generated
                return 0;
            }
        }
    }

    objDir = buildPath(repoRoot, "obj");
    if(!exists(objDir))
    {
        mkdir(objDir);
    }

    Appender!(Module[]) modules;
    foreach(entry; dirEntries(moreRoot, "*.d", SpanMode.breadth))
    {
        auto module_ = Module(entry.name.idup);
        writefln("Getting dependencies for %s (%s)", module_.name, module_.filename);
        
        callCompilerToGetDeps(module_.filename, null, &module_.normalDeps);
        callCompilerToGetDeps(module_.filename, " -unittest", &module_.unittestDeps);

        modules.put(module_);
    }
    // TODO: sort the modules in alphabetical order so the generated moduledeps.d file
    //       is always the same.  Also, maybe moduledeps.d should not be in the repo?

    writefln("Writing result to \"%s\"", outputFilename);
    {
        auto outFile = File(outputFilename, "w");
        scope(exit) outFile.close();

        outFile.outln("// This file is autogenerated by running 'rund generatedeps.d'");
        outFile.outln("module moduledeps;");
        outFile.outln();
        outFile.outln("enum M : ushort");
        outFile.outln("{");
        foreach(ref module_; modules.data)
        {
            outFile.outln("  %s,", module_.name);
        }
        outFile.outln("}");
        outFile.outln("@property string name(M mod)");
        outFile.outln("{");
        outFile.outln("    final switch(mod)");
        outFile.outln("    {");
        foreach(ref module_; modules.data)
        {
            outFile.outln("        case M.%s: return \"%s\";", module_.name, module_.name);
        }
        outFile.outln("    }");
        outFile.outln("}");
        outFile.outln("@property string filename(M mod)");
        outFile.outln("{");
        outFile.outln("    final switch(mod)");
        outFile.outln("    {");
        foreach(ref module_; modules.data)
        {
            outFile.outln("        case M.%s: return \"more/%s.d\";", module_.name, module_.name.replace("_", "/"));
        }
        outFile.outln("    }");
        outFile.outln("}");
        outFile.write(q{
struct ModuleDeps
{
    M module_;
    M[] deps;
}
});
        generateDepTable(outFile, modules.data, DepType.normal);
        generateDepTable(outFile, modules.data, DepType.unittest_);
    }
    return 0;
}

void callCompilerToGetDeps(T)(string filename, string extraArgs, T deps)
{
    auto compileCommand = format("dmd -v -c -od%s%s %s", objDir, extraArgs, filename);

    writefln("[RUN] %s", compileCommand);
    auto pipes = pipeShell(compileCommand, Redirect.stdout | Redirect.stderr);

    foreach(line; pipes.stdout.byLine)
    {
        //writeln(line);
        enum ImportLineStart = "import ";
        if(line.startsWith(ImportLineStart))
        {
            //writefln("IMPORTLINE: %s", line);
            auto limit = line.ptr + line.length;
            auto next = line.ptr + ImportLineStart.length;
            next = next.skipSpace(limit);
            enum MorePrefix = "more.";
            if(next.startsWith(limit, MorePrefix))
            {
                next += MorePrefix.length;
                auto end = next.findCharIndex('\t');
                auto dep = next[0..end].idup.replace(".", "_");
                writefln("  %s", dep);
                deps.put(dep);
            }
        }
    }
}

void generateDepTable(File outFile, Module[] modules, DepType type)
{
    outFile.outln("__gshared immutable %sDepTable = [", type.name);
    foreach(ref module_; modules)
    {
        outFile.writef("  immutable ModuleDeps(M.%s, [", module_.name);
        string prefix = "\n    ";
        foreach(ref dep; (type == DepType.normal) ? module_.normalDeps.data : module_.unittestDeps.data)
        {
            outFile.writef("%sM.%s", prefix, dep);
            prefix = ",\n    ";
        }
        outFile.outln("]),");
    }
    outFile.outln("];");
    outFile.outln("@property immutable(M)[] %sDeps(M module_)", type.name);
    outFile.outln("{");
    outFile.outln("    return %sDepTable[cast(ushort)module_].deps;", type.name);
    outFile.outln("}");
}