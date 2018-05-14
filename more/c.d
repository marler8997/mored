/**
Contains code to help interfacing with C code.
*/
module more.c;

import more.sentinel : SentinelPtr, StringLiteral;

// TODO: this definitions may change depending on the
//       platform.  These types are meant to be used
//       when declaring extern (C) functions who return
//       types int/unsigned.
alias cint = int;
alias cuint = uint;

/**
A `cstring`` is pointer to an array of characters that is terminated
with a '\0' (null) character.
*/
alias cstring = SentinelPtr!(const(char));
/// ditto
alias cwstring = SentinelPtr!(const(wchar));
/// ditto
alias cdstring = SentinelPtr!(const(dchar));

version(unittest)
{
    // demonstrate that C functions can be redefined using SentinelPtr
    extern(C) size_t strlen(cstring str);
}

unittest
{
    assert(5 == strlen(StringLiteral!"hello".ptr));

    // NEED MULTIPLE ALIAS THIS to allow SentinelArray to implicitly convert to SentinelPtr
    //assert(5 == strlen(StringLiteral!"hello"));

    // type of string literals should be changed to SentinelString in order for this to work
    //assert(5 == strlen("hello".ptr");

    // this requires both conditions above to work
    //assert(5 == strlen("hello"));
}

unittest
{
    import more.sentinel;

    char[10] buffer = void;
    buffer[0 .. 5] = "hello";
    buffer[5] = '\0';
    SentinelArray!char hello = buffer[0..5].verifySentinel;
    assert(5 == strlen(hello.ptr));
}

pragma(inline) auto tempCString(const(char)[] str)
{
    import more.sentinel : verifySentinel, assumeSentinel, SentinelArray;
    static import std.internal.cstring;
    static struct TempCString
    {
        typeof(std.internal.cstring.tempCString(str)) result;
        size_t length;
        SentinelPtr!(const(char)) ptr() inout { return result.ptr.assumeSentinel; }
        SentinelArray!(const(char)) array() inout { return result.ptr[0 .. length].assumeSentinel; }
        alias ptr this;
    }
    return TempCString(std.internal.cstring.tempCString(str), str.length);
}
