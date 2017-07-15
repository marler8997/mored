module more.utf8;

version(unittest_utf8)
{
    import std.stdio;
    import more.common;
}

version(unittest_utf8)
{
    import std.string;
}

//
// Utf8
//
private enum genericMessage = "invalid utf8";
private enum startedInsideCodePointMessage = "utf8 string started inside a utf8 code point";
private enum missingBytesMessage = "utf8 encoding is missing some bytes";
private enum outOfRangeMessage = "the utf8 code point is out of range";
class Utf8Exception : Exception
{
    enum Type
    {
        generic,
        startedInsideCodePoint,
        missingBytes,
        outOfRange,
    }
    static string getMessage(Type type)
    {
        final switch(type)
        {
          case Type.generic: return genericMessage;
          case Type.startedInsideCodePoint: return startedInsideCodePointMessage;
          case Type.missingBytes: return missingBytesMessage;
          case Type.outOfRange: return outOfRangeMessage;
        }
    }
    const Type type;
    this(Type type)
    {
        super(getMessage(type));
        this.type = type;
    }
}


// This method assumes that utf8 points to at least one character
// and that the first non-valid pointer is at the limit pointer
// (this means that utf8 < limit)
dchar decodeUtf8(ref inout(char)* utf8, const char* limit)
{
    dchar c = *utf8;
    utf8++;
    if(c <= 0x7F)
    {
        return c;
    }
    if((c & 0x40) == 0)
    {
        throw new Utf8Exception(Utf8Exception.Type.startedInsideCodePoint);
    }

    if((c & 0x20) == 0)
    {
        if(utf8 >= limit) throw new Utf8Exception(Utf8Exception.Type.missingBytes);
        return ((c << 6) & 0x7C0) | (*(utf8++) & 0x3F);
    }

    if((c & 0x10) == 0)
    {
        utf8++;
        if(utf8 >= limit) throw new Utf8Exception(Utf8Exception.Type.missingBytes);
        return ((c << 12) & 0xF000) | ((*(utf8 - 1) << 6) & 0xFC0) | (*(utf8++) & 0x3F);
    }

    if((c & 0x08) == 0)
    {
        utf8 += 2;
        if(utf8 >= limit) throw new Utf8Exception(Utf8Exception.Type.missingBytes);
        return ((c << 18) & 0x1C0000) | ((*(utf8 - 2) << 12) & 0x3F000) |
            ((*(utf8 - 1) << 6) & 0xFC0) | (*(utf8++) & 0x3F);
    }

    throw new Utf8Exception(Utf8Exception.Type.outOfRange);
}

//
// Copyright (c) 2008-2009 Bjoern Hoehrmann <bjoern@hoehrmann.de>
// See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/ for details.
//
dchar bjoernDecodeUtf8(ref inout(char)* utf8, const char* limit) {
  static __gshared immutable ubyte[] utf8lookup = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
    8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
    0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
    0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
    0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1, // s0..s0
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1, // s1..s2
    1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1, // s3..s4
    1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1, // s5..s6
    1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1, // s7..s8
  ];
  enum utf8Accept = 0;
  enum utf8Reject = 1;

  uint state = utf8Accept;
  dchar codep;

  while(true) {
    ubyte b = *utf8;
    uint type = utf8lookup[b];

    codep = (state != utf8Accept) ?
      (b & 0x3fu) | (codep << 6) : (0xff >> type) & b;

    state = utf8lookup[256 + state*16 + type];

    if(state == utf8Accept) return codep;
    if(state == utf8Reject) throw new Utf8Exception(Utf8Exception.Type.generic);
    utf8++;
    if(utf8 >= limit) throw new Utf8Exception(Utf8Exception.Type.missingBytes);
  }
}


version(unittest_utf8) unittest
{
  mixin(scopedTest!("utf8"));

  void testDecodeUtf8(inout(char)[] s, dchar[] expectedChars, size_t line = __LINE__) {
    auto start = s.ptr;
    auto limit = s.ptr + s.length;

    foreach(expected; expectedChars) {
      if(start >= limit) {
	writefln("Expected more decoded utf8 chars but input ended");
	writefln("test on line %s", line);
	assert(0);
      }
      auto saveStart = start;
      dchar decoded = decodeUtf8(start, limit);
      if(decoded != expected) {
	writefln("decodeUtf8: Expected '%s' 0x%x but decoded '%s' 0x%x",
		 expected, expected, decoded, decoded);
	writefln("test on line %s", line);
	assert(0);
      }
      start = saveStart;
      decoded = bjoernDecodeUtf8(start, limit);
      if(decoded != expected) {
	writefln("bjoernDecodeUtf8: Expected '%s' 0x%x but decoded '%s' 0x%x",
		 expected, expected, decoded, decoded);
	writefln("test on line %s", line);
	assert(0);
      }
      debug writefln("decodeUtf8('%s')", decoded);
    }
  }
  void testInvalidUtf8(Utf8Exception.Type expectedError, inout(char)[] s, size_t line = __LINE__) {
    auto start = s.ptr;
    auto limit = s.ptr + s.length;
    
    auto saveStart = start;
    try {
      dchar decoded = decodeUtf8(start, limit);
      assert(0, format("expected error '%s' but no error was thrown", expectedError));
    } catch(Utf8Exception e) {
      assert(e.type == expectedError, format("expected error '%s' but got '%s'", expectedError, e.type));
    }

    start = saveStart;
    try {
      dchar decoded = bjoernDecodeUtf8(start, limit);
      assert(0, format("expected error '%s' but no error was thrown", expectedError));
    } catch(Utf8Exception e) {
      assert(e.type == Utf8Exception.Type.generic || e.type == expectedError, format
	     ("expected error '%s' but got '%s'", expectedError, e.type));
    }
    debug writefln("got expected error '%s'", expectedError);
  }

  char[] testString = new char[256];
  dchar[] expectedCharsBuffer = new dchar[256];


  testInvalidUtf8(Utf8Exception.Type.startedInsideCodePoint, [0x80]);
  testInvalidUtf8(Utf8Exception.Type.missingBytes, [0xC0]);
  testInvalidUtf8(Utf8Exception.Type.missingBytes, [0xE0, 0x80]);


  //  dchar[] ranges =
  //    [0, 0x7F]
  for(char c = 0; c <= 0x7F; c++) {
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

