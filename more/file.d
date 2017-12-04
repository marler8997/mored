module more.file;

import std.stdio : File;
import std.typecons : Flag, Yes, No;

// Reads the file into a string
char[] readFile(const(char)[] filename, Flag!"addNull" addNull)
{
    import std.format : format;

    auto file = File(filename, "rb");
    scope(exit) file.close();

    auto fileSize = file.size();

    static if(fileSize.max > size_t.max)
    {
        size_t maxFileSize = size_t.max;
        if(addNull)
        {
            maxFileSize--;
        }
        if(fileSize > maxFileSize)
        {
            assert(0, format("file \"%s\" of size %s is too large to read into one buffer (max is %s)",
                filename, fileSize, maxFileSize));
        }
    }
    auto contents = new char[cast(size_t)(fileSize + (addNull ? 1 : 0))];
    auto readSize = file.rawRead(contents).length;

    assert(fileSize == readSize, format("rawRead only read %s bytes of %s byte file", readSize, fileSize));

    if(addNull)
    {
        contents[cast(size_t)fileSize] = '\0';
        return contents[0..$-1];
    }
    return contents;
}

unittest
{
    import more.test;
    mixin(scopedTest!"file");
    import std.file : thisExePath;

    auto exePath = thisExePath();
    auto exeContents = readFile(exePath, No.addNull);
    auto exeContentsWithNull = readFile(exePath, Yes.addNull);
    assert(exeContents.length == exeContentsWithNull.length);
}