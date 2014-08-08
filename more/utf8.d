module more.utf8;

import std.stdio;

//
// Utf8
//
class Utf8Exception : Exception {
  this(string msg) {
    super(msg);
  }
}

enum invalidEndMessage = "input ended with invalid UTF-8 character";

// This method assumes that utf8 points to at least one character
// and that the first non-valid pointer is at the limit pointer
// (this means that utf8 < limit)
dchar decodeUtf8(ref inout(char)* utf8, inout(char)* limit) {
  dchar c = *utf8;
  utf8++;
  if((c & 0x80) == 0) {
    return c;
  }

  if((c & 0x20) == 0) {
    if(utf8 >= limit) throw new Utf8Exception(invalidEndMessage);
    utf8++;
    return ((c << 6) & 0x7C0) | (*(utf8 - 1) & 0x3F);
  }


  throw new Exception("utf8 not fully implemented");
}

//
// Copyright (c) 2008-2009 Bjoern Hoehrmann <bjoern@hoehrmann.de>
// See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/ for details.
//
dchar bjoernDecodeUtf8(ref inout(char)* utf8, inout(char)* limit) {
  static __gshared ubyte utf8lookup[] = [
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
    if(state == utf8Reject) throw new Utf8Exception("Invalid utf8");
    utf8++;
    if(utf8 >= limit) throw new Utf8Exception(invalidEndMessage);
  }
}


unittest
{
  void testDecodeUtf8(string s, dchar[] expectedChars...) {
    dchar decoded;
    auto start = s.ptr;
    auto limit = s.ptr + s.length;

    foreach(expected; expectedChars) {
      if(start >= limit) {
	writefln("Expected more decoded utf8 chars but input ended");
	assert(0);
      }
      auto saveStart = start;
      decoded = decodeUtf8(start, limit);
      if(decoded != expected) {
	writefln("Expected '%s' 0x%x but decoded '%s' 0x%x",
		 expected, expected, decoded, decoded);
	assert(0);
      }
      start = saveStart;
      decoded = bjoernDecodeUtf8(start, limit);
      if(decoded != expected) {
	writefln("Expected '%s' 0x%x but decoded '%s' 0x%x",
		 expected, expected, decoded, decoded);
	assert(0);
      }
      writefln("decodeUtf8('%s')", decoded);
    }
  }

  testDecodeUtf8("\u0000", 0x0000);
  testDecodeUtf8("\u0001", 0x0001);

  testDecodeUtf8("\u00a9", 0xa9);
  testDecodeUtf8("\u00b1", 0xb1);
  testDecodeUtf8("\u02c2", 0x02c2);
}

