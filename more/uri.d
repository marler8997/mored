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
    mixin(scopedTest!"uri - parseScheme");

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
    mixin(scopedTest!"uri - formatUriEncoded");

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

// TODO: use a function defined in a more common modules
private bool contains(T)(const(T)[] haystack, const(T) needle)
{
    foreach (element; haystack)
    {
        if (element == needle)
            return true;
    }
    return false;
}

// bad points to the '%' of the bad URI encoding
void copyBadUriEncoding(char* dst, const(char)* bad, size_t max)
{
    for (size_t i = 0; ; i++)
    {
        if (i >= max)
        {
            dst[i] = '\0';
            break;
        }
        dst[i] = bad[i];
        if (!dst[i])
            break;
    }
}

/**
On success, returns a pointer to the terminating null character in
the dst buffer.

If the src buffer contains an invalid '%XX' sequence, this function will
stop decoding at that point copy the invalid sequence (along with a terminating
null) to the dst buffer and return a pointer to the start of the invalid sequence.

Note that dst and src can point to the same string.  The decoding is performed left-to-right
so it still works.
*/
char* uriDecode(const(char)* src, char* dst, const(char)[] terminatingChars = "\0")
{
    for(;;dst++)
    {
        char c = src[0];
        src++;
        if(c == '+') {
            dst[0] = ' ';
        } else if (c == '%') {
            c = src[0];
            src++;
            const hexNibble1 = hexValue(c);
            if(hexNibble1 == ubyte.max)
            {
                copyBadUriEncoding(dst, src - 2, 2);
                return dst;
            }
            c = src[0];
            src++;
            const hexNibble2 = hexValue(c);
            if(hexNibble2 == ubyte.max)
            {
                copyBadUriEncoding(dst, src - 3, 3);
                return dst;
            }
            dst[0] = cast(char)(hexNibble1 << 4 | hexNibble2);
        } else if (terminatingChars.contains(c)) {
            dst[0] = '\0';
            return dst; // success
        } else {
            dst[0] = c;
        }
    }
}

char* uriDecode(const(char)[] src, char* dst)
{
    return uriDecode(src.ptr, src.ptr + src.length, dst);
}
char* uriDecode(const(char)* src, const(char)* srcLimit, char* dst)
{
    import core.stdc.string : memcpy;

    for(;;dst++)
    {
        if (src >= srcLimit)
        {
            *dst = '\0';
            return dst;
        }
        char c = src[0];
        src++;
        if(c == '+') {
            dst[0] = ' ';
        } else if (c == '%') {
            if (src + 1 >= srcLimit)
            {
                 copyBadUriEncoding(dst, src - 1, 2);
                 return dst; // fail
            }
            c = src[0];
            src++;
            const hexNibble1 = hexValue(c);
            if(hexNibble1 == ubyte.max)
            {
                 copyBadUriEncoding(dst, src - 2, 2);
                 return dst; // fail
            }
            c = src[0];
            src++;
            const hexNibble2 = hexValue(c);
            if(hexNibble2 == ubyte.max)
            {
                 copyBadUriEncoding(dst, src - 3, 3);
                 return dst; // fail
            }
            dst[0] = cast(char)(hexNibble1 << 4 | hexNibble2);
        } else {
            dst[0] = c;
        }
    }
}

/**
Returns: null on error, the decoded string on success
*/
char[] tryUriDecodeInPlace(char* value, const(char)[] terminatingChars)
{
    auto result = uriDecode(value, value, terminatingChars);
    if (result[0] == '\0')
        return value[0 .. result - value];
    return null; // error
}

/**
Returns: a new null-terminated string or null on error
*/
char[] tryUriDecode(const(char)[] encoded)
{
    auto decoded = new char[encoded.length + 1];
    auto result = uriDecode(encoded, decoded.ptr);
    if (result[0] != '\0')
        return null; // fail
    return decoded[0 .. result - decoded.ptr];
}

unittest
{
    import core.stdc.stdlib : alloca;
    import core.stdc.string : strlen;
    mixin(scopedTest!("uri encode/decode"));
    static void test(const(char)[] before, const(char)[] expectedAfter)
    {
        {
            auto actualAfter = tryUriDecode(before);
            assert(actualAfter == expectedAfter);
        }
        static char[] makeCopy(const(char)[] str, const(char)[] postfix)
        {
            auto copy = new char[str.length + postfix.length];
            copy[0 .. str.length] = str[];
            copy[str.length .. $] = postfix[];
            return copy;
        }

        {
            auto actualAfter = cast(char*)alloca(before.length + 1);
            auto result = uriDecode(before.ptr, actualAfter);
            assert(result[0] == '\0');
            assert(actualAfter[0 .. result - actualAfter] == expectedAfter);
        }
        {
            auto copy = makeCopy(before, "&");
            auto actualAfter = cast(char*)alloca(before.length + 1);
            auto result = uriDecode(copy.ptr, actualAfter, "&");
            assert(result[0] == '\0');
            assert(actualAfter[0 .. result - actualAfter] == expectedAfter);
        }
        {
            auto copy = makeCopy(before, "\0");
            auto afterCopy = tryUriDecodeInPlace(copy.ptr, "\0");
            assert(afterCopy == expectedAfter);
        }
    }
    test("", "");
    test("a", "a");
    test("abcd", "abcd");
    test("abcd+efgh", "abcd efgh");
    test("a%00b%01c%02", "a\x00b\x01c\x02");
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

        test(str[0 .. 3], expected[0 .. 1]);

        str[1] = toHexUpper(cast(ubyte)(value >> 4));
        str[2] = toHexUpper(cast(ubyte)(value & 0x0F));

        test(str[0 .. 3], expected[0 .. 1]);
    }

    static void testError(const(char)[] badEncoding, const(char)[] badPart)
    {
        assert(!tryUriDecode(badEncoding));
        {
            auto actualAfter = cast(char*)alloca(badEncoding.length + 1);
            auto result =  uriDecode(badEncoding.ptr, actualAfter);
            assert(result[0 .. strlen(result)] == badPart);
        }
        {
            auto actualAfter = cast(char*)alloca(badEncoding.length + 1);
            auto result =  uriDecode(badEncoding, actualAfter);
            import std.stdio;writefln("badEncoding '%s' result '%s'", badEncoding, result[0 .. strlen(result)]);
            assert(result[0 .. strlen(result)] == badPart);
        }
    }
    testError("%", "%");
    testError("foo%", "%");
    testError("foo%a", "%a");
    testError("foo%aZ", "%aZ");
}
