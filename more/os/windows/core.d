module more.os.windows.core;

pragma(lib, "kernel32");

alias cint = int;
alias cuint = uint;

struct WindowsErrorCode
{
    private cint value;
    @property auto errorCode() const { return value; }
    @property bool failed() const { return value != 0; }
    @property bool passed() const { return value == 0; }
}
struct HANDLE
{
    private uint value;
    @property bool isValid() const { return value != 0; }
    @property bool isInvalid() const { return value == 0; }
}

alias extern (Windows) cint* function() nothrow FARPROC, NEARPROC, PROC;

extern(Windows) nothrow @nogc
{
    WindowsErrorCode GetLastError() @trusted;

    HANDLE GetModuleHandleA(const(char)* ModuleName);
    FARPROC GetProcAddress(HANDLE Module, const(char)* ProcName);
}

// Common return value for os functions
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
alias SysErrorCode = WindowsErrorCode;
SysErrorCode lastError()
{
    return GetLastError();
}
