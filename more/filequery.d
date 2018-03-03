module filequery;

import core.stdc.errno;
import std.typecons : Flag, Yes, No;
import std.file : FileException;
import std.traits : isNarrowString;

////////////////////////////////////////////////////////////////////////////////
// NOTE: this was copied from file.d
////////////////////////////////////////////////////////////////////////////////
// Character type used for operating system filesystem APIs
version (Windows)
{
    private alias FSChar = wchar;
}
else version (Posix)
{
    private alias FSChar = char;
}
else
    static assert(0);
private T cenforce(T)(T condition, lazy const(char)[] name, string file = __FILE__, size_t line = __LINE__)
{
    if (condition)
        return condition;
    version (Windows)
    {
        throw new FileException(name, .GetLastError(), file, line);
    }
    else version (Posix)
    {
        throw new FileException(name, .errno, file, line);
    }
}
version (Windows)
@trusted
private T cenforce(T)(T condition, const(char)[] name, const(FSChar)* namez,
    string file = __FILE__, size_t line = __LINE__)
{
    if (condition)
        return condition;
    if (!name)
    {
        import core.stdc.wchar_ : wcslen;
        import std.conv : to;

        auto len = namez ? wcslen(namez) : 0;
        name = to!string(namez[0 .. len]);
    }
    throw new FileException(name, .GetLastError(), file, line);
}

version (Posix)
@trusted
private T cenforce(T)(T condition, const(char)[] name, const(FSChar)* namez,
    string file = __FILE__, size_t line = __LINE__)
{
    if (condition)
        return condition;
    if (!name)
    {
        import core.stdc.string : strlen;

        auto len = namez ? strlen(namez) : 0;
        name = namez[0 .. len].idup;
    }
    throw new FileException(name, .errno, file, line);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////


static struct AllSupportedOps
{
    //
    // The following settings are named by the operations that we would want to support on the FileInfo.
    //
    /++
    If true, will cause queryFile to throw an exception if the file does not exist and
    modifies FileInfo to not have any representation for a non-existing file.
    +/
    enum bool exists = true;
    enum bool isFile = true;

    // Windows: GetFileAttributes FILE_ATTRIBUTE_DIRECTTORY
    // Posix: ...
    enum bool isDir  = true;
    // Windows: GetFileAttributes FILE_ATTRIBUTE_REPARSE_POINT
    enum bool isSymlink = true;
    // Windows: ?
    // Posix: stat/lstat st_size
    enum bool getSize = true;

    // Windows: ?
    // Posix: stat/lstat st_mtime
    enum bool timeLastModified = true;

    // Windows Specific
    enum bool isArchive = true;    // See GetFileAttributes FILE_ATTRIBUTE_ARCHIVE
    enum bool isCompressed = true; // See GetFileAttributes FILE_ATTRIBUTE_COMPRESSED
    enum bool isHidden = true;     // See GetFileAttributes FILE_ATTRIBUTE_HIDDEN
    enum bool isNormal = true;     // See GetFileAttributes FILE_ATTRIBUTE_NORMAL
    enum bool isReadOnly = true;   // See GetFileAttributes FILE_ATTRIBUTE_READONLY

    // Posix Specific
    enum bool getDeviceID = true;        // See stat.st_dev
    enum bool getInode = true;           // See stat.st_ino
    enum bool getMode = true;            // See stat.st_mode
    enum bool getHardLinkCount = true;   // See stat.st_nlink
    enum bool getUid = true;             // See stat.st_uid
    enum bool getGid = true;             // See stat.st_gid
    enum bool getSpecialDeviceID = true; // See stat.st_rdev
}

struct FileQueryEverythingEnabledExamplePolicy
{
    // Posix: with the stat function, you can get the info on the symbol link or on it's file.
    //        You do this by either calling `stat` or `lstat`.
    enum followSymlink = true;
    alias SupportedOps = AllSupportedOps;
}



template fileQueryTemplate(Policy)
{
    // TODO: static assert(isValidFileQueryPolicy(Policy));
    private bool supportOp(string name)
    {
        foreach(op; Policy.SupportedOps)
	{
	    if (op == name)
	    {
	        return true;
	    }
	}
        return false;
    }

    version(Windows)
    {
        private enum oneOrMoreAttributesSupported =
            (supportOp("isFile") ||
	     supportOp("isDir") ||
	     supportOp("isSymlink") ||
	     supportOp("isArchive") ||
	     supportOp("isCompressed") ||
	     supportOp("isHidden") ||
	     supportOp("isNormal") ||
	     supportOp("isReadOnly"));

        static if (oneOrMoreAttributesSupported)
        {
            enum useGetFileAttributes = oneOrMoreAttributesSupported;
	}
	else static if (supportOp("exists"))
	{
            // TODO: maybe in this case we should just use the PathFileExists function istead?
            enum useGetFileAttributes = true;
        }
        else
        {
	    enum useGetFileAttributes = false;
        }
    }
    else version(Posix)
    {

        // TODO: determine if we are going to use the stat function
	enum useStat = true;

        static if (useStat)
	{
            import core.sys.posix.sys.stat;
            static if (supportOp("exists"))
                enum saveStatSucceeded = true;
	    else
	        enum saveStatSucceeded = false;
	}
    }
    else static assert(0);

    struct FileInfo
    {
        version(Windows)
	{
            static if (useGetFileAttributes)
            {
                DWORD getFileAttributesResult;
            }
	}
	else
	{
	    static if (useStat)
	    {
	        stat_t statbuf;
                static if (saveStatSucceeded)
                {
                    bool statSucceeded;
                }
	    }
	    else static assert(0, "not implemented");
	}

        static if (supportOp("exists"))
        {
            @property bool exists()
            {
                version(Windows)
                {
                    static if (useGetFileAttributes)
                    {
                        return getFileAttributesResult != INVALID_FILE_ATTRIBUTES;
                    }
                    else static assert(0);
                }
		else version(Posix)
		{
		    static if (useStat)
		    {
		        return statSucceeded;
		    }
		    else static assert(0, "not implemented");
		}
                else static assert(0, "not implemented");
	    }
	}
        static if (supportOp("isFile"))
        {
            @property bool isFile()
            {
                version(Windows)
		{
		    static assert(0, "not implemented");
		}
		else version(Posix)
		{
		    static if (useStat)
		    {
                        return (statbuf.st_mode & S_IFMT) == S_IFREG;
		    }
		    else static assert(0, "not implemented");
		}
                else static assert(0, "not implemented");
            }
        }
    }

    
/*
    /// Note: If a symlink is passed in, this function will query the underlying file instead. 
    ///       You can use querySymlink to query the symlink itself.
    FileInfo query(R)(R name)
    {
        FileInfo info = void;
	query(&info, name);
	return info;
    }
    */
    /// ditto
    auto query(Policy, R)(FileInfo* outInfo, R name)
    {
        import std.internal.cstring : tempCString;
        version(Windows)
	{
	    static assert(0, "not implemented");
	}
	else version(Posix)
	{
	    static if (useStat)
	    {
                import core.sys.posix.sys.stat : stat;
		auto namez = name.tempCString();
		bool statSucceeded = (0 == stat(namez, &outInfo.statbuf));
		
	        static if(saveStatSucceeded)
		{
		    outInfo.statSucceeded = statSucceeded;
		}
		else
		{
                    static if (isNarrowString!R && is(Unqual!(ElementEncodingType!R) == char))
                        alias names = name;
                    else
                        string names = null;
                    cenforce(statSucceeded, names, namez);
		}
		if (!statSucceeded)
		{
		    static if (Policy.enforceExists)
		    {
		        
		    
		    }
		}
	    }
	}
        else assert(0, "not implemented");
    }
    version(Posix)
    {
        // query the symlink itself instead of the underlying file
        FileInfo querySymlink(R)(R name)
        {
            assert(0, "not implemented");
        }
    }
}
/+
struct SplitString
{
    string str;
    size_t splitStart;
    size_t splitEnd;
    @property string left() const { return str[0 .. splitStart]; }
    @property string right() const { return str[splitEnd .. $]; }
}
SplitString splitString(string str, char delimiter) pure
{
    size_t index;
    for (index = 0; index < str.length; index++)
    {
        if (str[index] == delimiter)
	{
	    return SplitString(str, index, index + 1);
	}
    }
    return SplitString(str, index, index);
}

template tuple(T...)
{
    alias tuple = T;
}
template OpTuple(string ops)
{
    static if (ops.length == 0)
    {
        alias OpTuple = tuple!();
    }
    else
    {
        private enum splitOps = splitString(ops, ',');
        alias OpTuple = tuple!(splitOps.left, OpTuple!(splitOps.right));
    }
}
+/
mixin template makeFileQuery(string[] options)
{
    static struct FileQueryPolicy
    {
        //alias SupportedOps = OpTuple!options;
        alias SupportedOps = options;
    }
    alias fileQuery = fileQueryTemplate!FileQueryPolicy;
}

unittest
{
    import std.stdio;
    {
        mixin makeFileQuery!(["exists"]);
	auto helloInfo = fileQuery.query("hello");
	writefln("helloInfo.exists = %s", helloInfo.exists);
    }
    {
        mixin makeFileQuery!(["isFile"]);
	auto helloInfo = fileQuery.query("hello");
	writefln("helloInfo.isFile = %s", helloInfo.isFile);
    }
}