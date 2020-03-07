module more.os.posix.core;

import more.types : passfail;
import more.c : cint;

/**
Common return value for os functions.
*/
struct SysResult
{
    private cint value;
    @property bool failed() const { return value != 0; }
    @property bool passed() const { return value == 0; }
}

/**
The generic type that represents a system error code as returned
by the `lastError` function.
*/
alias SysErrorCode = cint;
SysErrorCode lastError()
{
    import core.stdc.errno : errno;
    return errno;
}


/**
Represents a file handle
*/
struct FileHandle
{
    @property static FileHandle invalidValue()
    {
        return FileHandle(-1);
    }
    private cint _value;
    @property bool isInvalid() const
    {
        return _value < 0;
    }
    @property auto val() const { return cast(cint)_value; }
}

alias sysresult_t = cint;
pragma(inline)
@property bool failed(sysresult_t result)
{
    return result != 0;
}
pragma(inline)
@property bool success(sysresult_t result)
{
    return result == 0;
}

extern(C) nothrow @nogc
{
    cint fcntl(FileHandle file, cint command, ...);
    // TODO: probably split this into seperate function depending
    //       on the command, like this one
    import core.sys.posix.fcntl :
        F_DUPFD,
        F_GETFL,
        F_SETFL;
    public import core.sys.posix.fcntl :
        O_NONBLOCK;
    pragma(inline)
    FileHandle fcntlDupFD(FileHandle file)
    {
        return cast(FileHandle)fcntl(file, F_DUPFD);
    }
    struct FDFlags
    {
        cint flags;
        @property bool isInvalid() const pure @nogc { return flags == -1; }
        FDFlags opBinary(string op)(cint right)
        {
            mixin("return FDFlags(flags " ~ op ~ " right);");
        }
        FDFlags opBinaryRight(string op)(cint left)
        {
            mixin("return FDFlags(left " ~ op ~ " flags);");
        }
    }
    FDFlags fcntlGetFlags(FileHandle file)
    {
        return cast(FDFlags)fcntl(file, F_GETFL);
    }
    passfail fcntlSetFlags(FileHandle file, FDFlags flags)
        in { assert(!flags.isInvalid); } do
    {
        return (-1 == fcntl(file, F_SETFL, flags)) ? passfail.fail : passfail.pass;
    }
    sysresult_t close(FileHandle);
}

