module more.uri;

import more.format : toHexLower, toHexUpper, formatEscapeByPolicy;
import more.parse : hexValue;

version(unittest)
{
    import std.stdio : stdout;
    import more.test;
}

// http://www.ietf.org/rfc/rfc2396.txt
bool isValidSchemeFirstChar(char c)
{
    return
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z');
}
bool isValidSchemeChar(char c)
{
    return
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        (c == '+') ||
        (c == '-') ||
        (c == '.');
}
/** Returns: 0 if no scheme is found, otherwise, returns the length of the scheme
             including the colon character */
uint parseScheme(const(char)[] uri)
{
    if(uri.length > 0 && isValidSchemeFirstChar(uri[0]))
    {
        uint index = 1;
        foreach(char_; uri[1..$])
        {
            if(char_ == ':')
            {
                return cast(uint)index + 1;
            }
            if(!isValidSchemeChar(char_))
            {
                break;
            }
            index++;
        }
    }
    return 0;
}
unittest
{
    assert(0 == parseScheme(null));
    assert(0 == parseScheme(""));
    assert(0 == parseScheme("a"));
    assert(0 == parseScheme("/"));
    assert(0 == parseScheme(":"));
    assert(2 == parseScheme("a:"));
    assert(4 == parseScheme("abc:"));

    assert(0 == parseScheme("0bc:"));
    assert(0 == parseScheme("-bc:"));
    assert(0 == parseScheme("+bc:"));
    assert(0 == parseScheme(".bc:"));
    assert(0 == parseScheme(".bc:"));

    assert(5 == parseScheme("a0bc:"));
    assert(5 == parseScheme("a-bc:"));
    assert(5 == parseScheme("a+bc:"));
    assert(5 == parseScheme("a.bc:"));
    assert(5 == parseScheme("a.bc:"));
}

bool isValidUriChar(char c) pure
{
    if(c >= 'a')
    {
        if(c <= 'z' || c == '~')
        {
            return true;
        }
    }
    else if(c >= 'A')
    {
        if(c <= 'Z' || c == '_')
        {
            return true;
        }
    }
    else if(c >= '-')
    {
        if(c <= '9' && c != '/')
        {
            return true;
        }
    }
    return false;
}
auto formatUriEncoded(const(char)[] str)
{
    static struct Hooks
    {
        enum escapeBufferLength = 3;
        static void initEscapeBuffer(char* escapeBuffer) pure
        {
        }
        static auto escapeCheck(char* escapeBuffer, char charToCheck) pure
        {
            if(charToCheck == ' ')
            {
                escapeBuffer[0] = '+';
                return 1;
            }
            if(isValidUriChar(charToCheck))
            {
                return 0; // no need to escape
            }
            escapeBuffer[0] = '%';
            escapeBuffer[1] = toHexUpper((cast(ubyte)charToCheck) >> 4);
            escapeBuffer[2] = toHexUpper((cast(ubyte)charToCheck) & 0x0F);
            return 3; // write a 3 character '%XX' escape sequence
        }
    }
    return formatEscapeByPolicy!Hooks(str);
}
unittest
{
    import std.format : format;
    assert(`` == format("%s", formatUriEncoded(``)));
    assert(`a` == format("%s", formatUriEncoded(`a`)));
    assert(`abcd` == format("%s", formatUriEncoded(`abcd`)));
    assert(`abcd+efgh` == format("%s", formatUriEncoded(`abcd efgh`)));
    assert(`%00%0A%21%2F` == format("%s", formatUriEncoded("\0\n!/")));
    for(int i = char.min; i <= char.max; i++)
    {
        char[1] str;
        str[0] = cast(char)i;

        if(str[0] == ' ') {
            assert("+" == format("%s", formatUriEncoded(str)));
        } else if(isValidUriChar(str[0])) {
            char[1] expected;
            expected[0] = cast(char)i;
            assert(expected == format("%s", formatUriEncoded(str)));
        } else {
            char[3] expected;
            expected[0] = '%';
            expected[1] = toHexUpper((cast(ubyte)i) >> 4);
            expected[2] = toHexUpper((cast(ubyte)i) & 0x0F);
            assert(expected == format("%s", formatUriEncoded(str)));
        }
    }
}

/**
 On success, returns a pointer to the terminating null character in
 the dst buffer.

 If the src buffer contains an invalid '%XX' sequence, this function will
 stop decoding at that point copy the invalid sequence (along with a terminating
 null) to the dst buffer and return a pointer to the start of the invalid sequence.
*/
char* uriDecode(const(char)* src, char* dst)
{
    //log("uriDecode before \"%s\"", src[0..strlen(src)]);
    //auto saveDst = dst;
    //scope(exit) log("uriDecode after  \"%s\"", saveDst[0..strlen(saveDst)]);
    for(;;dst++) {
        char c = *src;
        src++;
        if(c == '+') {
            *dst = ' ';
        } else if (c == '%') {
            char[2] hexChars = void;
            hexChars[0] = *src;
            src++;

            ubyte hexNibble1 = hexValue(hexChars[0]);
            if(hexNibble1 == ubyte.max) {
              dst[0..2] = (src - 1)[0..2];
              dst[2] = '\0';
              return dst;
            }

            hexChars[1] = *src;
            src++;

            ubyte hexNibble2 = hexValue(hexChars[1]);
            if(hexNibble2 == ubyte.max) {
              dst[0..3] = (src - 2)[0..3];
              dst[3] = '\0';
              return dst;
            }

            *dst = cast(char)(hexNibble1 << 4 | hexNibble2);

        } else if (c == '\0') {
            *dst = '\0';
            return dst;
        } else {
            *dst = c;
        }
    }
}
unittest
{
    import core.stdc.stdlib : alloca;
    mixin(scopedTest!("uri encode/decode"));
    void test(const(char)[] before, const(char)[] expectedAfter)
    {
        assert(before[$-1] == '\0');
        auto actualAfter = cast(char*)alloca(before.length);
        auto result = uriDecode(before.ptr, actualAfter);
        assert(actualAfter[0 .. (result + 1) - actualAfter] == expectedAfter);
    }
    test("\0", "\0");
    test("a\0", "a\0");
    test("abcd\0", "abcd\0");
    test("abcd+efgh\0", "abcd efgh\0");
    test("a%00b%01c%02\0", "a\x00b\x01c\x02\0");
    for(ushort valueAsUShort = ubyte.min; valueAsUShort <= ubyte.max; valueAsUShort++) {
        auto value = cast(ubyte)valueAsUShort;
        char[2] expected;
        expected[0] = cast(char)value;
        expected[1] = '\0';

        char[4] str;
        str[0] = '%';
        str[1] = toHexLower(cast(ubyte)(value >> 4));
        str[2] = toHexLower(cast(ubyte)(value & 0x0F));
        str[3] = '\0';

        test(str, expected);

        str[1] = toHexUpper(cast(ubyte)(value >> 4));
        str[2] = toHexUpper(cast(ubyte)(value & 0x0F));

        test(str, expected);
    }
}
