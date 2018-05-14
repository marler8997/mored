module more.format;

/**
Used for selecting either lower or upper case for certain kinds of formatting, such as hex.
*/
enum Case
{
    lower, upper
}

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
void putf(R, U...)(auto ref R outputRange, string fmt, U args)
{
    import std.format : formattedWrite;
    formattedWrite(&outputRange.put!(const(char)[]), fmt, args);
}

/**
Converts a 4-bit nibble to the corresponding hex character (0-9 or A-F).
*/
char toHex(Case case_ = Case.lower)(ubyte b) in { assert(b <= 0x0F); } body
{
    /*
    NOTE: another implementation could be to use a hex table such as:
       return "0123456789ABCDEF"[value];
    HoweverThe table lookup might be slightly worse since it would require
    the string table to be loaded into the processor cache, whereas the current
    implementation may be more instructions but all the code will
    be in the same place which helps cache locality.

    On processors without cache (such as the 6502), the table lookup approach
    would likely be faster.
      */
    static if(case_ == Case.lower)
    {
        return cast(char)(b + ((b <= 9) ? '0' : ('a'-10)));
    }
    else
    {
        return cast(char)(b + ((b <= 9) ? '0' : ('A'-10)));
    }
}
unittest
{
    assert('0' == toHex(0x0));
    assert('9' == toHex(0x9));
    assert('a' == toHex(0xA));
    assert('f' == toHex(0xF));
    assert('A' == toHex!(Case.upper)(0xA));
    assert('F' == toHex!(Case.upper)(0xF));
}
alias toHexLower = toHex!(Case.lower);
alias toHexUpper = toHex!(Case.upper);

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
        buffer[2] = toHexUpper((cast(char)c)>>4);
        buffer[3] = toHexUpper((cast(char)c)&0xF);
        sink(buffer);
    }
}
void asciiWriteEscaped(scope void delegate(const(char)[]) sink, const(char)* ptr, const char* limit)
{
    auto flushPtr = ptr;

    void flush()
    {
        if(ptr > flushPtr)
        {
            sink(flushPtr[0..ptr-flushPtr]);
            flushPtr = ptr;
        }
    }

    for(; ptr < limit; ptr++)
    {
        auto c = *ptr;
        if(asciiIsUnreadable(c))
        {
            flush();
            sink.asciiWriteUnreadable(c);
            flushPtr++;
        }
    }
    flush();
}
auto asciiFormatEscaped(const(char)[] str)
{
    static struct Formatter
    {
        const(char)* str;
        const(char)* limit;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            sink.asciiWriteEscaped(str, limit);
        }
    }
    return Formatter(str.ptr, str.ptr + str.length);
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
        buffer[2] = toHexUpper((cast(char)c)>>4);
        buffer[3] = toHexUpper((cast(char)c)&0xF);
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
        auto c = decodeUtf8(&nextPtr);
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

auto formatHex(Case case_ = Case.lower, T)(const(T)[] array) if(T.sizeof == 1)
{
    struct Formatter
    {
        const(T)[] array;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            char[2] chars;
            foreach(value; array)
            {
                chars[0] = toHex!case_((cast(char)value)>>4);
                chars[1] = toHex!case_((cast(char)value)&0xF);
                sink(chars);
            }
        }
    }
    return Formatter(array);
}

// Policy-based formatEscape function
auto formatEscapeByPolicy(Hooks)(const(char)[] str)
{
    struct Formatter
    {
        const(char)[] str;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            auto from = 0;
            auto to = 0;
            char[Hooks.escapeBufferLength] buffer;
            Hooks.initEscapeBuffer(buffer.ptr);

            for(; to < str.length; to++)
            {
                auto escapeLength = Hooks.escapeCheck(buffer.ptr, str[to]);
                if(escapeLength > 0)
                {
                    if(to > from)
                    {
                        sink(str[from..to]);
                    }
                    sink(buffer[0..escapeLength]);
                    from = to + 1;
                }
            }
            if(to > from)
            {
                sink(str[from..to]);
            }
        }
    }
    return Formatter(str);
}
auto formatEscapeSet(string escapePrefix, string escapeSet)(const(char)[] str)
{
    static struct Hooks
    {
        enum escapeBufferLength = escapePrefix.length + 1;
        static void initEscapeBuffer(char* escapeBuffer) pure
        {
            escapeBuffer[0..escapePrefix.length] = escapePrefix[];
        }
        static auto escapeCheck(char* escapeBuffer, char charToCheck) pure
        {
            foreach(escapeChar; escapeSet)
            {
                if(charToCheck == escapeChar)
                {
                    escapeBuffer[escapePrefix.length] = charToCheck;
                    return escapePrefix.length + 1;
                }
            }
            return 0; // char should not be escaped
        }
    }
    return formatEscapeByPolicy!Hooks(str);
}
unittest
{
    import more.test;
    mixin(scopedTest!"format");

    import std.format : format;
    assert(`` == format("%s", formatEscapeSet!(`\`, `\'`)(``)));
    assert(`a` == format("%s", formatEscapeSet!(`\`, `\'`)(`a`)));
    assert(`abcd` == format("%s", formatEscapeSet!(`\`, `\'`)(`abcd`)));

    assert(`\'` == format("%s", formatEscapeSet!(`\`, `\'`)(`'`)));
    assert(`\\` == format("%s", formatEscapeSet!(`\`, `\'`)(`\`)));
    assert(`\'\\` == format("%s", formatEscapeSet!(`\`, `\'`)(`'\`)));
    assert(`a\'\\` == format("%s", formatEscapeSet!(`\`, `\'`)(`a'\`)));
    assert(`\'a\\` == format("%s", formatEscapeSet!(`\`, `\'`)(`'a\`)));
    assert(`\'\\a` == format("%s", formatEscapeSet!(`\`, `\'`)(`'\a`)));
    assert(`abcd\'\\` == format("%s", formatEscapeSet!(`\`, `\'`)(`abcd'\`)));
    assert(`\'abcd\\` == format("%s", formatEscapeSet!(`\`, `\'`)(`'abcd\`)));
    assert(`\'\\abcd` == format("%s", formatEscapeSet!(`\`, `\'`)(`'\abcd`)));
}
