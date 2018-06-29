module more.utf8;

import std.typecons : Flag, Yes, No;

version(unittest)
{
    import more.test;
    import std.stdio;
    import std.string;
}

class Utf8Exception : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure
    {
        super(msg, file, line);
    }
}
class Utf8DecodeException : Utf8Exception
{
    enum Type : ubyte
    {
        invalidFirstByte,
        missingBytes,
        outOfRange,
    }
    @property static auto invalidFirstByte(string file = __FILE__, size_t line = __LINE__)
    {
        return new Utf8DecodeException(Type.invalidFirstByte,
            "a utf8 code point starts with an invalid byte", file, line);
    }
    @property static auto missingBytes(string file = __FILE__, size_t line = __LINE__)
    {
        return new Utf8DecodeException(Type.missingBytes,
            "a utf8 code point is missing one or more bytes", file, line);
    }
    @property static auto outOfRange(string file = __FILE__, size_t line = __LINE__)
    {
        return new Utf8DecodeException(Type.outOfRange,
            "a utf8 code point is out of range", file, line);
    }
    const Type type;
    private this(Type type, string msg, string file = __FILE__, size_t line = __LINE__) pure
    {
        super(msg, file, line);
        this.type = type;
    }
}

/**
Decodes a single UTF8 character from the given buffer. $(D utf8InOut) is
used to pass in the start of the utf8 encoded character, and also used to
return the end of it once it has been decoded.

Returns the decoded character as a 32-bit dchar.

Throw: $(D Utf8DecodeException) if the utf8 encoding is invalid.
*/
pragma(inline)
dchar decodeUtf8(T)(T** utf8InOut) pure if(T.sizeof == 1)
{
    return decodeUtf8Impl!(No.useLimit)(cast(const(char)**)utf8InOut);
}
/// ditto
pragma(inline)
dchar decodeUtf8(T)(T** utf8InOut, T* limit) if(T.sizeof == 1)
{
    return decodeUtf8Impl!(Yes.useLimit)(cast(const(char)**)utf8InOut, cast(const(char)*) limit);
}

template decodeUtf8Impl(Flag!"useLimit" useLimit)
{
    private enum MixinCode = q{
        auto utf8 = *utf8InOut;
        scope(exit)
        {
            *utf8InOut = utf8;
        }
        dchar first = *utf8;
        utf8++;
        if(first <= 0x7F)
        {
            return first;
        }
        static if(useLimit)
        {
            if((first & 0x40) == 0)
            {
                throw Utf8DecodeException.invalidFirstByte();
            }
        }
        if((first & 0x20) == 0)
        {
            static if(useLimit)
            {
                if(utf8 >= limit) throw Utf8DecodeException.missingBytes;
            }
            return ((first << 6) & 0x7C0) | (*(utf8++) & 0x3F);
        }
        if((first & 0x10) == 0)
        {
            utf8++;
            static if(useLimit)
            {
                if(utf8 >= limit) throw Utf8DecodeException.missingBytes;
            }
            return ((first << 12) & 0xF000) | ((*(utf8 - 1) << 6) & 0xFC0) | (*(utf8++) & 0x3F);
        }

        if((first & 0x08) == 0)
        {
            utf8 += 2;
            static if(useLimit)
            {
                if(utf8 >= limit) throw Utf8DecodeException.missingBytes;
            }
            return ((first << 18) & 0x1C0000) | ((*(utf8 - 2) << 12) & 0x3F000) |
                ((*(utf8 - 1) << 6) & 0xFC0) | (*(utf8++) & 0x3F);
        }

        throw Utf8DecodeException.outOfRange;
  };
  static if(useLimit)
  {
    dchar decodeUtf8Impl(const(char)** utf8InOut, const(char)* limit) pure
    {
      mixin(MixinCode);
    }
  }
  else
  {
    dchar decodeUtf8Impl(const(char)** utf8InOut) pure
    {
      mixin(MixinCode);
    }
  }
}

unittest
{
    mixin(scopedTest!("decodeUtf8"));

    void testDecodeUtf8(inout(char)[] s, dchar[] expectedChars, size_t line = __LINE__)
    {
        auto start = s.ptr;
        auto limit = s.ptr + s.length;

        foreach(expected; expectedChars)
        {
            if(start >= limit)
            {
                writefln("Expected more decoded utf8 chars but input ended");
                writefln("test on line %s", line);
                assert(0);
            }
            auto saveStart = start;
            dchar decoded = decodeUtf8(&start, limit);
            if(decoded != expected)
            {
                writefln("decodeUtf8: Expected '%s' 0x%x but decoded '%s' 0x%x",
                expected, expected, decoded, decoded);
                writefln("test on line %s", line);
                assert(0);
            }
            //debug writefln("decodeUtf8('%s')", decoded);
        }
    }
    void testInvalidUtf8(Utf8DecodeException.Type expectedError, inout(char)[] s, size_t line = __LINE__)
    {
        auto start = s.ptr;
        auto limit = s.ptr + s.length;

        auto saveStart = start;
        try
        {
            dchar decoded = decodeUtf8(&start, limit);
            assert(0, format("expected error '%s' but no error was thrown", expectedError));
        }
        catch(Utf8DecodeException e)
        {
            assert(e.type == expectedError, format("expected error '%s' but got '%s'", expectedError, e.type));
        }
    }

    char[] testString = new char[256];
    dchar[] expectedCharsBuffer = new dchar[256];

    testInvalidUtf8(Utf8DecodeException.Type.invalidFirstByte, [0x80]);
    testInvalidUtf8(Utf8DecodeException.Type.missingBytes, [0xC0]);
    testInvalidUtf8(Utf8DecodeException.Type.missingBytes, [0xE0, 0x80]);

    //  dchar[] ranges =
    //    [0, 0x7F]
    for(char c = 0; c <= 0x7F; c++)
    {
        testString[0] = c;
        expectedCharsBuffer[0] = c;
        testDecodeUtf8(testString[0..1], expectedCharsBuffer[0..1]);
    }

    testDecodeUtf8("\u0000", [0x0000]);
    testDecodeUtf8("\u0001", [0x0001]);

    testDecodeUtf8("\u00a9", [0xa9]);
    testDecodeUtf8("\u00b1", [0xb1]);
    testDecodeUtf8("\u02c2", [0x02c2]);


    testDecodeUtf8("\u0080", [0x80]);
    testDecodeUtf8("\u07FF", [0x7FF]);

    testDecodeUtf8("\u0800", [0x800]);
    testDecodeUtf8("\u7fff", [0x7FFF]);
    testDecodeUtf8("\u8000", [0x8000]);
    testDecodeUtf8("\uFFFD", [0xFFFD]);
    //testDecodeUtf8("\uFFFE", [0xFFFE]); // DMD doesn't like this code point
    //testDecodeUtf8("\uFFFF", [0xFFFF]); // DMD doesn't like this code point

    testDecodeUtf8("\U00010000", [0x10000]);
    testDecodeUtf8("\U00100000", [0x00100000]);
    testDecodeUtf8("\U0010FFFF", [0x0010FFFF]);
    //testDecodeUtf8("\U00110000", [0x00110000]); // DMD doesn't like this code point
}

class Utf8EncodeException : Utf8Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure
    {
        super(msg, file, line);
    }
}

/**
Encodes a single character into the given buffer
Returns the number of bytes used to encode the given character.
*/
ubyte encodeUtf8(char* dst, dchar c)
{
    if(c <= 0x7F)
    {
        *dst++ = cast(char)c;
        return 1;
    }
    if(c <= 0x7FF)
    {
        *dst++ = cast(char)(192+c/64);
        *dst++ = cast(char)(128+c%64);
        return 2;
    }
    if(c <= 0xFFFF)
    {
        *dst++ = cast(char)(224+c/4096);
        *dst++ = cast(char)(128+c/64%64);
        *dst++ = cast(char)(128+c%64);
        return 3;
    }
    if(c <= 0x1FFFFF)
    {
        *dst++ = cast(char)(240+c/262144);
        *dst++ = cast(char)(128+c/4096%64);
        *dst++ = cast(char)(128+c/64%64);
        *dst++ = cast(char)(128+c%64);
        return 4;
    }
    import std.format;
    throw new Utf8EncodeException(format("encodeUtf8 got a value that was too large (0x%x)", c));
}

unittest
{
    mixin(scopedTest!("full utf8 encode/decode"));
    for(dchar c = 0; ;c++)
    {
        char[4] buffer;
        auto encodeLength = encodeUtf8(buffer.ptr, c);
        {
            auto utf8 = buffer.ptr;
            auto decoded = decodeUtf8(&utf8);
            assert(utf8 - buffer.ptr == encodeLength);
            assert(decoded == c);
        }
        {
            auto utf8 = buffer.ptr;
            auto decoded = decodeUtf8(&utf8, utf8 + encodeLength);
            assert(utf8 - buffer.ptr == encodeLength);
            assert(decoded == c);
        }
        if(c == dchar.max)
        {
            break;
        }
    }
}
