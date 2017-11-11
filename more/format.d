module more.format;

import std.typecons : Flag, Yes, No;

/**
An alias to the common sink delegate used for string formatting.
*/
alias StringSink = scope void delegate(const(char)[]);

/**
A delegate formatter allows a delegate to behave as format function.
A common use case for this would be to have multiple ways to format a class.

Example:
---
class Foo
{
    DelegateFormatter formatPretty() { return DelegateFormatter(&prettyFormatter); }
    private void prettyFormatter(StringSink sink)
    {
        sink("the pretty format");
    }

    DelegateFormatter formatUgly() { return DelegateFormatter(&uglyFormatter); }
    private void uglyFormatter(StringSink sink)
    {
        sink("the ugly format");
    }
}
Foo foo;
writefln("foo pretty = %s", foo.formatPretty());
writefln("foo ugly   = %s", foo.formatUgly());
---

*/
struct DelegateFormatter
{
    void delegate(StringSink sink) formatter;
    void toString(StringSink sink) const
    {
        formatter(sink);
    }
}

/**
Append a formatted string into a character OutputRange
*/
void putf(R, U...)(R outputRange, string fmt, U args)
{
    formattedWrite(&outputRange.put!(const(char)[]), fmt, args);
}

/**
Converts a 4-bit nibble to the corresponding hex character (0-9 or A-F).
*/
char hexchar(Flag!"upperCase" upperCase = Yes.upperCase)(ubyte b) in { assert(b <= 0x0F); } body
{
    static if(upperCase)
    {
        return cast(char)(b + ((b <= 9) ? '0' : ('A'-10)));
    }
    else
    {
        return cast(char)(b + ((b <= 9) ? '0' : ('a'-10)));
    }
}
unittest
{
    assert('0' == hexchar(0x0));
    assert('9' == hexchar(0x9));
    assert('A' == hexchar(0xA));
    assert('F' == hexchar(0xF));
    assert('a' == hexchar!(No.upperCase)(0xA));
    assert('f' == hexchar!(No.upperCase)(0xF));
}

bool asciiIsUnreadable(char c) pure nothrow @nogc @safe
{
    return c < ' ' || (c > '~' && c < 256);
}

void asciiWriteUnreadable(scope void delegate(const(char)[]) sink, char c)
    in { assert(asciiIsUnreadable(c)); } body
{
    if(c == '\r') sink("\\r");
    else if(c == '\t') sink("\\t");
    else if(c == '\n') sink("\\n");
    else if(c == '\0') sink("\\0");
    else {
        char[4] buffer;
        buffer[0] = '\\';
        buffer[1] = 'x';
        buffer[2] = hexchar((cast(char)c)>>4);
        buffer[3] = hexchar((cast(char)c)&0xF);
        sink(buffer);
    }
}

bool utf8IsUnreadable(dchar c) pure nothrow @nogc @safe
{
    if(c < ' ') return true; // unreadable
    if(c < 0x7F) return false; // readable
    assert(0, "utf8IsUnreadable not fully implemented");
}
void utf8WriteUnreadable(scope void delegate(const(char)[]) sink, dchar c)
    in { assert(utf8IsUnreadable(c)); } body
{
    if(c == '\r') sink("\\r");
    else if(c == '\t') sink("\\t");
    else if(c == '\n') sink("\\n");
    else if(c == '\0') sink("\\0");
    else {
        if(c >= 0xFF)
        {
            assert(0, "not implemented");
        }
        char[4] buffer;
        buffer[0] = '\\';
        buffer[1] = 'x';
        buffer[2] = hexchar((cast(char)c)>>4);
        buffer[3] = hexchar((cast(char)c)&0xF);
        sink(buffer);
    }
}
void utf8WriteEscaped(scope void delegate(const(char)[]) sink, const(char)* ptr, const char* limit)
{
    import more.utf8 : decodeUtf8;

    auto flushPtr = ptr;

    void flush()
    {
        if(ptr > flushPtr)
        {
            sink(flushPtr[0..ptr-flushPtr]);
            flushPtr = ptr;
        }
    }

    for(; ptr < limit;)
    {
        const(char)* nextPtr = ptr;
        dchar c = decodeUtf8(&nextPtr);
        if(utf8IsUnreadable(c))
        {
            flush();
            sink.utf8WriteUnreadable(c);
        }
        ptr = nextPtr;
    }
    flush();
}
auto utf8FormatEscaped(const(char)[] str)
{
    static struct Formatter
    {
        const(char)* str;
        const(char)* limit;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            sink.utf8WriteEscaped(str, limit);
        }
    }
    return Formatter(str.ptr, str.ptr + str.length);
}
auto utf8FormatEscaped(dchar c)
{
    static struct Formatter
    {
        char[4] buffer;
        ubyte size;
        this(dchar c)
        {
            import more.utf8 : encodeUtf8;
            size = encodeUtf8(buffer.ptr, c);
        }
        void toString(scope void delegate(const(char)[]) sink) const
        {
            sink.utf8WriteEscaped(buffer.ptr, buffer.ptr + size);
        }
    }
    return Formatter(c);
}