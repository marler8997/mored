module more.common;

import std.ascii;
import std.conv;
import std.range;
import std.stdio;
import std.string;
import std.bitmanip;
import std.format;

import core.exception;

import std.c.string : memmove;

version(unittest)
{
  import std.array;
}


void implement(string feature = "", string file = __FILE__, int line = __LINE__) {
  string msg = "not implemented";
  if(feature.length) {
    msg = feature~' '~msg;
  }
  throw new Exception(msg, file, line);
}

float stdTimeMillis(long stdTime)
{
  return cast(float)stdTime / 10000f;
}
string prettyTime(float millis)
{
  if (millis < 0) return "-"~prettyTime(-millis);
    
  if (millis < 1000)
    return to!string(millis)~" millis";
  if (millis < 60000)
    return to!string(millis / 1000)~" seconds";
  if (millis < 3600000)
    return to!string(millis / 60000)~" minutes";
  if (millis < 86400000)
    return to!string(millis / 3600000)~" hours";
  return to!string(millis / 86400000)~" days";
}

template isChar(T) {
  static if(is(T == char) ||
	    is(T == const char) ||
	    is(T == immutable char))
    enum isChar = true;
  else
    enum isChar = false;
}

template ArrayElementType(Type)
{
  static if(is(Type : E[], E))
    alias ArrayElementType = E;
  else
    alias ArrayElementType = void;
}
template TypeTupleStrings(alias sep, T...)
{
  static if(T.length == 0) {
    immutable string TypeTupleStrings = "";
  } else static if(T.length == 1) {
    immutable string TypeTupleStrings = T[0].stringof;
  } else {
    immutable string TypeTupleStrings = T[0].stringof ~ sep ~ TypeTupleStrings!(sep, T[1..$]);
  }
}
template TupleRange(int from, int to) if (from <= to) {
  static if (from >= to) {
    alias TupleRange = TypeTuple!();
  } else {
    alias TupleRange = TypeTuple!(from, TupleRange!(from + 1, to));
  }
}

public interface IDisposable
{
  void dispose();
}


enum outerBar = "=========================================";
enum innerBar = "-----------------------------------------";
void startTest(string name)
{
  writeln(outerBar);
  writeln(name, ": Start");
  writeln(innerBar);
}
void endFailedTest(string name)
{
  writeln(innerBar);
  writeln(name, ": Failed");
  writeln(outerBar);
}
void endPassedTest(string name)
{
  writeln(innerBar);
  writeln(name, ": Passed");
  writeln(outerBar);
}
template scopedTest(string name) {
  enum scopedTest =
    "startTest(\""~name~"\");"~
    "scope(failure) {stdout.flush();endFailedTest(\""~name~"\");}"~
    "scope(success) endPassedTest(\""~name~"\");";
}
void writeSection(string name)
{
  writeln(innerBar);
  writeln(name);
  writeln(innerBar);
}
void assertEqual(string expected, string actual) pure
{
  if(expected != actual) {
    throw new AssertError(format("Expected %s Actual %s",
				 expected ? ('"' ~ expected ~ '"') : "<null>",
				 actual   ? ('"' ~ actual   ~ '"') : "<null>"));
  }
}

template Unroll(alias CODE, alias N, alias SEP="")
{
    enum NEW_CODE = replace(CODE, "%", "%1$d");
    enum Unroll = iota(N).map!(i => format(NEW_CODE, i)).join(SEP);
}
template UnrollTuple(alias CODE, alias SEP, T...)
{
    enum NEW_CODE = replace(CODE, "%", "%1$d");
    enum UnrollTuple = T.map!(t => format(NEW_CODE, t)).join(SEP);
}


public alias DataHandler = void delegate(ubyte[] data);
public alias StringHandler = void delegate(string data);
public interface IDataHandler : IDisposable
{
  void handleData(ubyte[] data);
}

string debugChar(char c)
{
  switch(c) {
  case '\r':return r"'\r'";
  case '\n':return r"'\n'";
  default:
    if(isPrintable(c)) return "'" ~ c ~ "'";
    return to!string(cast(uint)c);
  }
}

void dcpy(void* destination, const ubyte[] source) pure nothrow
{
  (cast(ubyte*)destination)[0..source.length][] = source;
}
void dcpy(void* destination, const char[] source) pure nothrow
{
  (cast(char*)destination)[0..source.length][] = source;
}
/+
void dcpy(Source)(void * destination, Source source) pure nothrow
{
  (cast(ubyte*)destination)[0..source.length][] = source;
}
+/

/+
void trimNewline(ref inout(char)[] line) {
  // remove ending characters
  while(true) {
    if( line.length <= 0 || (line[$-1] != '\n' && line[$-1] != '\r') ) return;
    line = line[0..$-1];
  }
}
+/

void trimNewline(inout(char)[]* line) {
  // remove ending characters
  while(true) {
    if( (*line).length <= 0 || ((*line)[$-1] != '\n' && (*line)[$-1] != '\r') ) return;
    (*line) = (*line)[0..$-1];
  }
}


version(unittest_common) unittest
{
  mixin(scopedTest!("trimNewline"));

  void testTrimNewline(string s, string expected) {
    //writef("'%s' => ", escape(s));
    trimNewline(&s);
    //writefln("'%s'", escape(s));
    assert(expected == s);
  }

  testTrimNewline("", "");
  testTrimNewline("\r", "");
  testTrimNewline("\n", "");
  testTrimNewline("1234", "1234");
  testTrimNewline("abcd  \n", "abcd  ");
  testTrimNewline("hello\r\r\r\n\n\r\r\n", "hello");

}


void readFullSize(File file, char[] buffer) {
  while(true) {
    char[] lastRead = file.rawRead(buffer);
    if(lastRead.length == buffer.length) return;
    if(lastRead.length == 0) throw new Exception("File did not have enough data left to fill the buffer");
    buffer = buffer[lastRead.length..$];
  }
}

// returns true on success, false if the file reached EOF
bool tryReadFullSize(File file, char[] buffer) {
  while(true) {
    char[] lastRead = file.rawRead(buffer);
    if(lastRead.length == buffer.length) return true;
    if(lastRead.length == 0) return false;
    buffer = buffer[lastRead.length..$];
  }
}

alias ubyte[] function(ubyte[] oldBuffer, size_t newLength, bool copy) Allocator;
alias void function(ubyte[] buffer) Deallocator;

ubyte[] defaultAllocator(ubyte[] oldBuffer, size_t newLength, bool copy)
{
  oldBuffer.length = newLength;
  return oldBuffer;
}
void defaultDeallocator(ubyte[] buffer)
{
  // do nothing, the garbage collector handles it
}
alias CustomLineParser!(defaultAllocator, defaultDeallocator) LineParser;

template CustomLineParser(A...)
{
struct CustomLineParser
{
  size_t expandLength;

  ubyte[] buffer;

  ubyte *lineStart;       // Points to the start of the next line
  size_t lineCheckOffset; // Offset from lineStart to the next character to check
  size_t lineDataLimit;   // Length from lineStart to the end of the data

  public this(ubyte[] buffer, size_t expandLength = 256)
  {
    this.expandLength = expandLength;

    this.buffer = buffer;
    this.lineStart = buffer.ptr;
    this.lineCheckOffset = 0;
    this.lineDataLimit = 0;
  }
  @property public void put(Data)(Data data) if ( (*data.ptr).sizeof == 1 )
  {
    debug writefln("[debug] ---> put(%4d bytes) : start %d check %d limit %d",
		   data.length, (lineStart - buffer.ptr), lineCheckOffset, lineDataLimit);

    size_t newDataOffset = (lineStart - buffer.ptr) + lineDataLimit;
    size_t bytesLeft = buffer.length - newDataOffset;

    if(bytesLeft < data.length) {
      size_t lineStartOffset = lineStart - buffer.ptr;
      size_t defaultExpandLength = this.buffer.length + this.expandLength;
      size_t neededLength = newDataOffset + data.length;

      //this.buffer.length = (neededLength >= defaultExpandLength) ? neededLength : defaultExpandLength;
      ubyte[] newBuffer = A[0](this.buffer, (neededLength >= defaultExpandLength) ? neededLength : defaultExpandLength, true);
      A[1](this.buffer);
      this.buffer = newBuffer;

      lineStart = this.buffer.ptr + lineStartOffset;
    }

    dcpy(lineStart + lineDataLimit, data);
    lineDataLimit += data.length;

    debug writefln("[debug] <--- put             : start %d check %d limit %d",
		   (lineStart - buffer.ptr), lineCheckOffset, lineDataLimit);
  }

  /// Returns null when it has parsed all the lines that have been added
  public ubyte[] getLine()
  {
    debug writefln("[debug] ---> getLine         : start %d check %d limit %d",
		   (lineStart - buffer.ptr), lineCheckOffset, lineDataLimit);

    while(lineCheckOffset < lineDataLimit) {
      debug {
	char c = lineStart[lineCheckOffset];
	writefln("[debug] start[%s] = %s", lineCheckOffset, debugChar(c));
      }
      if(lineStart[lineCheckOffset] == '\n') {
	ubyte[] line;
	if(lineCheckOffset > 0 && lineStart[lineCheckOffset - 1] == '\r') {
	  line = lineStart[0..lineCheckOffset - 1];
	} else {
	  line = lineStart[0..lineCheckOffset];
	}
	lineCheckOffset++;
	lineDataLimit -= lineCheckOffset;
	if(lineDataLimit > 0) {
	  lineStart = lineStart + lineCheckOffset;
	} else {
	  lineStart = buffer.ptr;
	}
	lineCheckOffset = 0;

	debug writefln("[debug] <--- getLine line    : start %d check %d limit %d",
		       (lineStart - buffer.ptr), lineCheckOffset, lineDataLimit);
	return line;
      }
      lineCheckOffset++;
    }

    if(lineStart == buffer.ptr) {
      debug writeln("[debug] No data");
      return null;
    }

    assert(lineDataLimit > 0);

    //
    // Move remaining data to the beginning of the buffer
    //
    debug writeln("[debug] Moving line data to beginning of buffer");
    memmove(buffer.ptr, lineStart, lineDataLimit);
    lineStart = buffer.ptr;
    debug {
      foreach(i,c; lineStart[0..lineDataLimit]) {
	writefln("[debug] line[%s] = %s", i, debugChar(c));
      }
    }
    debug writefln("[debug] <--- getLine no-line : start %d check %d limit %d",
		   (lineStart - buffer.ptr), lineCheckOffset, lineDataLimit);
    return null;
  }
}

}
version(unittest_common) unittest
{
  mixin(scopedTest!("LineParser"));

  void TestLineParser(LineParser lineParser)
  {
    lineParser.put("\n");
    assertEqual("", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("\r\n");
    assertEqual("", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("\r\r\n");
    assertEqual("\r", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("\n\n\n");
    assertEqual("", cast(string)lineParser.getLine());
    assertEqual("", cast(string)lineParser.getLine());
    assertEqual("", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("\r\r\r\n\r\n\n\r\r\r\n");
    assertEqual("\r\r", cast(string)lineParser.getLine());
    assertEqual("", cast(string)lineParser.getLine());
    assertEqual("", cast(string)lineParser.getLine());
    assertEqual("\r\r", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("abcd\n");
    assertEqual("abcd", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("abcd\r\n");
    assertEqual("abcd", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("abcd\nefgh\r\n");
    assertEqual("abcd", cast(string)lineParser.getLine());
    assertEqual("efgh", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("abcd\r\nefghijkl");
    assertEqual("abcd", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());
    lineParser.put("\n");
    assertEqual("efghijkl", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("abcd\n");
    lineParser.put("abcd\r\n");
    lineParser.put("abcd\n");
    assertEqual("abcd", cast(string)lineParser.getLine());
    assertEqual("abcd", cast(string)lineParser.getLine());
    assertEqual("abcd", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());

    lineParser.put("a");
    assert(!lineParser.getLine());
    lineParser.put("bc");
    assert(!lineParser.getLine());
    lineParser.put("d");
    assert(!lineParser.getLine());
    lineParser.put("\r\ntu");
    lineParser.put("v");
    assertEqual("abcd", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());
    lineParser.put("\r");
    assert(!lineParser.getLine());
    lineParser.put("\n");
    assertEqual("tuv", cast(string)lineParser.getLine());
    assert(!lineParser.getLine());
  }

  TestLineParser(LineParser([],1));
  TestLineParser(LineParser([0,0,0], 3));
  TestLineParser(LineParser(new ubyte[256]));
}


enum noEndingQuoteMessage = "found '\"' with no ending '\"'";

/**
 * Used to parse the fields in <i>line</i> to the <i>fields</i> sink.
 * line is a single line without the line ending character.
 * returns error message on error
 */
string tryParseFields(string comment = "#", T, C)(T fields, C[] line) if(isOutputRange!(T,C))
{
  size_t off = 0;
  size_t startOfField;

  Unqual!C c;

  while(true) {

    // Skip whitespace
    while(true) {
      if(off >= line.length) return null;
      c = line[off];
      if(c != ' ' && c != '\t') break;
      off++;
    }

    // check for comment
    static if(comment != null && comment.length == 1) {

      if(c == comment[0]) return null;

    } else static if(comment != null && comment.length > 1) {

      if(c == comment[0]) {
	size_t i = 1;
	while(true) {
	  if(off + i > line.length) break;
	  c = line[off + i];
	  if(c != comment[i]) break;

	  i++;
	  if(i >= comment.length) return null;
	}

	c = comment[0]; // restore state
      }

    }

    if(c == '"') {
      off++;
      startOfField = off;
      while(true) {
	if(off >= line.length) return noEndingQuoteMessage;
	c = line[off];
	if(c == '"') {
	  fields.put(line[startOfField..off]);
	  break;
	}
	if(c == '\\') {
	  throw new Exception("Escaping string not implemented yet");
	}
	off++;
      }
    } else {
      startOfField = off;
      while(true) {
	off++;
	if(off >= line.length) {
	  fields.put(line[startOfField..$]);
	  return null;
	}
	c = line[off];
	if(c == ' ' || c == '\t') {
	  fields.put(line[startOfField..off]);
	  break;
	}
      }
    }
  }
}

version(unittest_common) unittest
{
  mixin(scopedTest!("tryParseFields"));

  string line;
  auto fields = appender!(string[])();

  line = "\"Missing ending quote";
  assert(tryParseFields(fields, line) == noEndingQuoteMessage);

  line = "\"Missing ending quote\n";
  assert(tryParseFields(fields, line) == noEndingQuoteMessage);

  line = "\"Missing ending quote\nOn next line \"";
  assert(tryParseFields(fields, line) == noEndingQuoteMessage);

  line = "";
  assert(tryParseFields(fields, line) == null);
}


void bigEndianSetUshort(ubyte* bytes, ushort value)
{
  *bytes       = cast(ubyte)(value >> 8);
  *(bytes + 1) = cast(ubyte)(value     );
}
struct ArrayList(V)
{
  public V[] array;
  public size_t count;

  this(size_t initialSize)
  {
    if(initialSize < 1) throw new Exception("Cannot give an initial size of 0");
    array = new V[initialSize];
    count = 0;
  }
  this(Range)(Range r)
  {
    array = new V[r.length];
    foreach(i, element; r) {
      array[i] = element;
    }
    count = r.length;
  }
  void clear()
  {
    count = 0;
  }
  void checkSizeBeforeAdd()
  {
    if(count >= array.length) {
      array.length *= 2;
    }
  }
  public void put(V element)
  {
    checkSizeBeforeAdd();
    array[count++] = element;
  }
  public void forwardTo(Sink)(Sink sink)
  {
    foreach(i; 0..count) {
      sink.add(array[i]);
    }
  }
  public void removeAt(size_t index)
  {
    for(uint i = index; i < count - 1; i++) {
      array[index] = array[index + 1];
    }
    count--;
  }
}


immutable string[] escapeTable =
  [
   "\\0"  ,
   "\\x01",
   "\\x02",
   "\\x03",
   "\\x04",
   "\\x05",
   "\\x06",
   "\\a",  // Bell
   "\\b",  // Backspace
   "\\t",
   "\\n",
   "\\v",  // Vertical tab
   "\\f",  // Form feed
   "\\r",
   "\\x0E",
   "\\x0F",
   "\\x10",
   "\\x11",
   "\\x12",
   "\\x13",
   "\\x14",
   "\\x15",
   "\\x16",
   "\\x17",
   "\\x18",
   "\\x19",
   "\\x1A",
   "\\x1B",
   "\\x1C",
   "\\x1D",
   "\\x1E",
   "\\x1F",
   " ", //
   "!", //
   "\"", //
   "#", //
   "$", //
   "%", //
   "&", //
   "'", //
   "(", //
   ")", //
   "*", //
   "+", //
   ",", //
   "-", //
   ".", //
   "/", //
   "0", //
   "1", //
   "2", //
   "3", //
   "4", //
   "5", //
   "6", //
   "7", //
   "8", //
   "9", //
   ":", //
   ";", //
   "<", //
   "=", //
   ">", //
   "?", //
   "@", //
   "A", //
   "B", //
   "C", //
   "D", //
   "E", //
   "F", //
   "G", //
   "H", //
   "I", //
   "J", //
   "K", //
   "L", //
   "M", //
   "N", //
   "O", //
   "P", //
   "Q", //
   "R", //
   "S", //
   "T", //
   "U", //
   "V", //
   "W", //
   "X", //
   "Y", //
   "Z", //
   "[", //
   "\\", //
   "]", //
   "^", //
   "_", //
   "`", //
   "a", //
   "b", //
   "c", //
   "d", //
   "e", //
   "f", //
   "g", //
   "h", //
   "i", //
   "j", //
   "k", //
   "l", //
   "m", //
   "n", //
   "o", //
   "p", //
   "q", //
   "r", //
   "s", //
   "t", //
   "u", //
   "v", //
   "w", //
   "x", //
   "y", //
   "z", //
   "{", //
   "|", //
   "}", //
   "~", //
   "\x7F", //
   "\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8A", "\x8B", "\x8C", "\x8D", "\x8E", "\x8F",
   "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9A", "\x9B", "\x9C", "\x9D", "\x9E", "\x9F",
   "\xA0", "\xA1", "\xA2", "\xA3", "\xA4", "\xA5", "\xA6", "\xA7", "\xA8", "\xA9", "\xAA", "\xAB", "\xAC", "\xAD", "\xAE", "\xAF",
   "\xB0", "\xB1", "\xB2", "\xB3", "\xB4", "\xB5", "\xB6", "\xB7", "\xB8", "\xB9", "\xBA", "\xBB", "\xBC", "\xBD", "\xBE", "\xBF",
   "\xC0", "\xC1", "\xC2", "\xC3", "\xC4", "\xC5", "\xC6", "\xC7", "\xC8", "\xC9", "\xCA", "\xCB", "\xCC", "\xCD", "\xCE", "\xCF",
   "\xD0", "\xD1", "\xD2", "\xD3", "\xD4", "\xD5", "\xD6", "\xD7", "\xD8", "\xD9", "\xDA", "\xDB", "\xDC", "\xDD", "\xDE", "\xDF",
   "\xE0", "\xE1", "\xE2", "\xE3", "\xE4", "\xE5", "\xE6", "\xE7", "\xE8", "\xE9", "\xEA", "\xEB", "\xEC", "\xED", "\xEE", "\xEF",
   "\xF0", "\xF1", "\xF2", "\xF3", "\xF4", "\xF5", "\xF6", "\xF7", "\xF8", "\xF9", "\xFA", "\xFB", "\xFC", "\xFD", "\xFE", "\xFF",
   ];
string escape(char c) {
  return escapeTable[c];
}
string escape(dchar c) {
  return (c < escapeTable.length) ? escapeTable[c] : to!string(c);
}
inout(char)[] escape(inout(char)[] str) pure {
  size_t extra = 0;
  foreach(c; str) {
    if(c == '\r' || c == '\t' || c == '\n' || c == '\\') {
      extra++;
    }
  }

  if(extra == 0) return str;

  char[] newString = new char[str.length + extra];
  size_t oldIndex, newIndex = 0;
  for(oldIndex = 0; oldIndex < str.length; oldIndex++) {
    auto c = str[oldIndex];
    switch(c) {
    case '\r':
      newString[newIndex++] = '\\';
      newString[newIndex++] = 'r';
      break;
    case '\t':
      newString[newIndex++] = '\\';
      newString[newIndex++] = 't';
      break;
    case '\n':
      newString[newIndex++] = '\\';
      newString[newIndex++] = 'n';
      break;
    case '\\':
      newString[newIndex++] = '\\';
      newString[newIndex++] = '\\';
      break;
    default:
      newString[newIndex++] = c;
    }
  }

  assert(newIndex == newString.length);

  return cast(inout(char)[])newString;
}
version(unittest_common) unittest
{
  mixin(scopedTest!("escape"));

  assert (char.max == escapeTable.length - 1);

  for(auto c = ' '; c <= '~'; c++) {
    assert(c == escape(c)[0]);
  }
  assert("\\0" == escape(0));
  assert("\\r" == escape('\r'));
  assert("\\n" == escape('\n'));
  assert("\\t" == escape('\t'));


  assert("\\r" == escape("\r"));
  assert("\\t" == escape("\t"));
  assert("\\n" == escape("\n"));
  assert("\\\\" == escape("\\"));
}


struct StdoutWriter
{
  void put(const (char)[] str) {
    write(str);
  }
}

struct ReadBuffer(T)
{
  const(T)* next;
  const T* limit;
}
struct WriteBuffer(T)
{
  T* next;
  const T* limit;
  this(T[] array) {
    this.next = array.ptr;
    this.limit = array.ptr + array.length;
  }
  T[] slice(T* start) {
    return start[0..next-start];
  }
  void put(const(T)[] array) {
    if(next + array.length > limit)
      throw new Exception(format("buffer has %s elements left but you tried to add %s",
				 limit - next, array.length));

    foreach(value; array) {
      *next = value;
      next++;
    }
  }
}

alias void delegate(const(char)[] msg) const Writer;

alias size_t delegate(char[] buffer) CharReader;
alias size_t delegate(ubyte[] buffer) DataReader;

struct FileCharReader
{
  File file;
  size_t read(char[] buffer) {
    return file.rawRead(buffer).length;
  }
}

struct AsciiBufferedInput
{
  CharReader reader;
  char[] buffer;
  size_t start;
  size_t limit;

  this(inout(char)[] s) {
    this.reader = &emptyRead;
    this.buffer = new char[s.length + 1];
    this.buffer[0..$-1] = s;
    this.start = 0;
    this.limit = s.length;
  }
  private size_t emptyRead(char[] buffer) { return 0; }

  char[] sliceSaved() {
    return buffer[start..limit];
  }

  void clear() {
    start = 0;
    limit = 0;
  }

  // returns true if there is data, false on EOF
  bool readNoSave() {
    start = 0;
    limit = reader(buffer);
    return limit > 0;
  }

  // returns true if read succeeded, false on EOF
  bool read(size_t* offsetToShift) {
    //writefln("[DEBUG] --> read(start=%s, limit=%s)", start, limit);
    size_t leftover = limit - start;

    if(leftover) {
      if(leftover >= buffer.length) {
	throw new Exception("Buffer not large enough");
      }

      if(start > 0) {
	memmove(buffer.ptr, buffer.ptr + start, leftover);
	*offsetToShift -= leftover;
      }
    }

    start = 0;
    limit = leftover;
    size_t readLength = reader(buffer[leftover..$]);
    if(readLength == 0) {
      //writefln("[DEBUG] <-- read(start=%s, length=%s) = false", start, length);
      return false;
    }

    limit += readLength;
    return true;
  }


}


struct FormattedBinaryWriter
{
  scope void delegate(const(char)[]) sink;

  ubyte[] columnBuffer;


  string offsetFormat;
  mixin(bitfields!
	(bool, "hex", 1,
	 bool, "text", 1,
	 void, "", 6));

  size_t cachedData;

  uint offset;

  this(scope void delegate(const(char)[]) sink, ubyte[] columnBuffer,
       ubyte offsetTextWidth = 8, bool hex = true, bool text = true) {
    this.sink = sink;
    this.columnBuffer = columnBuffer;

    if(offsetTextWidth == 0) {
      offsetFormat = null;
    } else {
      offsetFormat = "%0"~to!string(offsetTextWidth)~"x";
    }

    this.hex = hex;
    this.text = text;
  }

  void writeAscii(byte b) {
    if(b <= '~' && b >= ' ') {
      sink((cast(char*)&b)[0..1]);
    } else {
      sink(".");
    }
  }

  void writeRow(T)(T data) {
    bool atFirst = true;
    void prefix() {
      if(atFirst) {atFirst = false; }
      else { sink(" "); }
    }
    if(offsetFormat) {
      prefix();
      formattedWrite(sink, offsetFormat, offset);
    }

    if(hex) {
      prefix();
      foreach(b; data) {
	formattedWrite(sink, " %02x", b);
      }
    }

    if(text) {
      prefix();
      foreach(b; data) {
	writeAscii(b);
      }
    }

    sink("\n");
    offset += columnBuffer.length;
  }
  void finish() {
    if(cachedData > 0) {
      bool atFirst = true;
      void prefix() {
	if(atFirst) {atFirst = false; }
	else { sink(" "); }
      }
      if(offsetFormat) {
	prefix();
	formattedWrite(sink, offsetFormat, offset);
      }

      if(hex) {
	prefix();
	foreach(b; columnBuffer[0..cachedData]) {
	  formattedWrite(sink, " %02x", b);
	}
	foreach(b; cachedData..columnBuffer.length) {
	  sink("   ");
	}
      }

      if(text) {
	prefix();
	foreach(b; columnBuffer[0..cachedData]) {
	  writeAscii(b);
	}
      }

      sink("\n");
      offset += columnBuffer.length;
    }
  }
  void put(scope ubyte[] data) {
    if(cachedData > 0) {
      implement();
    }

    while(data.length >= columnBuffer.length) {
      writeRow(data[0..columnBuffer.length]);
      data = data[columnBuffer.length..$];
    }
      
    if(data.length > 0) {
      columnBuffer[0..data.length][] = data;
      cachedData = data.length;
    }
  }
}



//
// Range Initializers
//
string arrayRange(char min, char max, string initializer) {
  string initializers = "";
  for(char c = min; c < max; c++) {
    initializers ~= "'"~c~"': "~initializer~",\n";
  }
  initializers ~= "'"~max~"': "~initializer;
  return initializers;
}
string rangeInitializers(string[] s...) {
  if(s.length % 2 != 0) assert(0, "must supply an even number of arguments to rangeInitializers");
  string code = "["~rangeInitializersCurrent(s);
  //assert(0, code); // uncomment to see the code
  return code;
}
string rangeInitializersCurrent(string[] s) {
  string range = s[0];
  if(range[0] == '\'') {
    if(range.length == 3 || (range.length == 4 && range[1] == '\\')) {
      if(range[$-1] != '\'') throw new Exception(format("a single-character range %s started with an apostrophe (') but did not end with one", range));
      return range ~ ":" ~ s[1] ~ rangeInitializersNext(s);
    }
  } else {
    throw new Exception(format("range '%s' not supported", range));
  }
  char min = range[1];
  char max = range[5];
  return arrayRange(min, max, s[1]) ~ rangeInitializersNext(s);
}
string rangeInitializersNext(string[] s...) {
  if(s.length <= 2) return "]";
  return ",\n"~rangeInitializersCurrent(s[2..$]);
}



struct StringByLine
{
  string s;
  size_t startOfLineOffset;
  size_t endOfLineOffset;
  this(string s) @safe pure nothrow @nogc
  {
    this.s = s;
    this.startOfLineOffset = 0;
    this.endOfLineOffset = 0;
    popFront;
  }
  @property bool empty() pure nothrow @safe @nogc
  {
    return startOfLineOffset >= s.length;
  }
  @property auto front() pure nothrow @safe @nogc
  {
    return s[startOfLineOffset..endOfLineOffset];
  }
  @property void popFront() pure nothrow @safe @nogc
  {
    if(startOfLineOffset < s.length) {
      startOfLineOffset = endOfLineOffset;
      while(true) {
	if(endOfLineOffset >= s.length) break;
	if(s[endOfLineOffset] == '\n') {
	  endOfLineOffset++;
	  break;
	}
	endOfLineOffset++;
      }
    }
  }
}
auto byLine(string s) pure nothrow @safe @nogc {
  return StringByLine(s);
}
version(unittest_common) unittest
{
  mixin(scopedTest!("StringByLine"));
  
  void test(string[] expectedStrings, string s, size_t testLine = __LINE__)
  {
    auto stringByLine = s.byLine();

    foreach(expectedString; expectedStrings) {
      if(stringByLine.empty) {
	writefln("Expected string '%s' but no more strings", escape(expectedString));
	assert(0);
      }
      if(expectedString != stringByLine.front) {
	writefln("Expected: '%s'", escape(expectedString));
	writefln("Actual  : '%s'", escape(stringByLine.front));
	assert(0);
      }
      stringByLine.popFront;
    }

    if(!stringByLine.empty) {
      writefln("Expected no more strings but got another '%s'", escape(stringByLine.front));
      assert(0);
    }
  }

  test([], "");
  test(["a"], "a");
  test(["a\n"], "a\n");
  test(["abc"], "abc");
  test(["abc\n"], "abc\n");

  test(["abc\n", "123"], "abc\n123");
  test(["abc\n", "123\n"], "abc\n123\n");

}



enum BufferTooSmall
{
  returnPartialData,
  throwException,
  resizeBuffer,
}

/**
   The LinesChunker reads as many lines as it can.  If the buffer runs out in the
   middle of a line it will return all the previous full lines.  On the next
   read it will move the left over data to the beginning of the buffer and continue reading.
   If it cannot read a full line it will either return partial lines or it will throw an
   error depending on what the user specifies.
   Options on how to handle lines that are too long
     1. Return partial lines
     2. Resize the buffer to hold the entire line
     3. Throw an exception/cause an error
*/
struct LinesChunker
{
  char[] buffer;
  BufferTooSmall tooSmall;
  private char[] leftOver;
  
  this(char[] buffer, BufferTooSmall tooSmall) {
    this.buffer = buffer;
    this.tooSmall = tooSmall;
  }
  size_t read(CharReader reader)
  {
    //
    // Handle leftOver Data
    //
    size_t bufferOffset;
    if(leftOver.length == 0) {
      bufferOffset = 0;
    } else {
      // TODO: do I need this check? Can this ever happen?
      if(leftOver.ptr != buffer.ptr) {
	memmove(buffer.ptr, leftOver.ptr, leftOver.length);
      }
      bufferOffset = leftOver.length;
      leftOver = null;
    }

    //
    // Read More Data
    //
    while(true) {
      if(bufferOffset >= buffer.length) {
	if(tooSmall == BufferTooSmall.returnPartialData) {
	  return bufferOffset;
	} else if(tooSmall == BufferTooSmall.resizeBuffer) {
	  throw new Exception("BufferTooSmall.resizeBuffer is not implemented in LinesChunker");
	}
	throw new Exception(format("the current buffer of length %s is too small to hold the current line", buffer.length));
      }

      size_t readLength = reader(buffer[bufferOffset .. $]);
      if(readLength == 0) return bufferOffset;

      auto totalLength = bufferOffset + readLength;
      auto i = totalLength - 1;
      while(true) {
	auto c = buffer[i];
	if(c == '\n') {
	  leftOver = buffer[i+1..totalLength];
	  return i+1;
	}
	if(i == bufferOffset) {
	  break;
	}
	i--;
      }

      bufferOffset = totalLength;
    }
  }
}

version(unittest_common)
{
  struct CustomChunks {
    string[] chunks;
    size_t chunkIndex;
    size_t read(char[] buffer) {
      if(chunkIndex >= chunks.length) return 0;
      auto chunk = chunks[chunkIndex++];
      if(chunk.length > buffer.length) {
	assert(0, format("Chunk at index %s is %s bytes but the buffer is only %s", chunkIndex, chunk.length, buffer.length));
      }
      buffer[0..chunk.length] = chunk;
      return chunk.length;
    }
  }
}
struct LinesReader
{
  CharReader reader;
  LinesChunker chunker;
  size_t currentBytes;
  this(CharReader reader, char[] buffer, BufferTooSmall tooSmall)
  {
    this.reader = reader;
    this.chunker = LinesChunker(buffer, tooSmall);
    this.currentBytes = this.chunker.read(reader);
  }
  @property empty()
  {
    return currentBytes == 0;
  }
  @property char[] front() {
    return chunker.buffer[0..currentBytes];
  }
  @property void popFront() {
    this.currentBytes = this.chunker.read(reader);
  }
}
auto byLines(CharReader reader, char[] buffer, BufferTooSmall tooSmall) {
  return LinesReader(reader, buffer, tooSmall);
}
auto byLines(File file, char[] buffer, BufferTooSmall tooSmall) {
  auto fileCharReader = FileCharReader(file);
  return LinesReader(&(fileCharReader.read), buffer, tooSmall);
}


version(unittest_common) unittest
{
  mixin(scopedTest!("LinesChunker/LinesReader"));

  CustomChunks customChunks;
  char[5] buffer5;
  char[256] buffer256;

  void testLinesChunkerCustom(string[] expectedChunks, CharReader reader, char[] chunkerBuffer = buffer256, size_t testLine = __LINE__)
  {
    auto lineChunker = LinesChunker(chunkerBuffer, BufferTooSmall.throwException);

    foreach(expectedChunk; expectedChunks) {
      size_t actualLength = lineChunker.read(reader);
      if(chunkerBuffer[0..actualLength] != expectedChunk) {
	writefln("Expected: '%s'", escape(expectedChunk));
	writefln("Actual  : '%s'", escape(chunkerBuffer[0..actualLength]));
	assert(0);
      }
/+
      debug {
	writefln("
      }
+/
    }
  }
  void testLinesChunker(string[] expectedChunks, string[] customChunkStrings, char[] chunkerBuffer = buffer256, size_t testLine = __LINE__)
  {
    writefln("testLinesChunker %s %s", expectedChunks, customChunkStrings);

    customChunks = CustomChunks(customChunkStrings);
    testLinesChunkerCustom(expectedChunks, &(customChunks.read), chunkerBuffer, testLine);
  }
  
  
  testLinesChunker(["a\n"], ["a\n"]);
  testLinesChunker(["a\n", "b"], ["a\nb"], buffer5); // NOTE: One would think that this should return one chunk, however,
                                                     //       This simulates the case when the reader returned the available
                                                     //       data so there's no way for the chunker to know if there is another newline
                                                     //       coming at the next read call so it just returns the currently known lines

  testLinesChunker(["a\nb\r\nc\n"], ["a\nb\r\nc\n"]);
  testLinesChunker(["a\nb\r\nc\n", "d"], ["a\nb\r\nc\nd"]);
  testLinesChunker(["123\n", "123\n"], ["123\n1", "23\n"], buffer5);
  testLinesChunker(["123\n", "123"], ["123\n1", "23"], buffer5);

  //
  // Test LinesReader
  //
/+
  void testByLines(string[] expectedChunks, string[] customChunkStrings, char[] cunkBuffer = buffer256, size_t testLine = __LINE__)
  {
    
  }
+/
  customChunks = CustomChunks(["a\nb"]);
  foreach(lines; (&(customChunks.read)).byLines(buffer5, BufferTooSmall.throwException)) {
    writefln("lines: '%s'", escape(lines));
  }
}


struct LineReader
{
  CharReader reader;
  LinesChunker chunker;

  size_t dataLength;
  char[] line;
  size_t endOfLineOffset;

  this(CharReader reader, char[] buffer, BufferTooSmall tooSmall) {
    this.reader = reader;
    this.chunker = LinesChunker(buffer, tooSmall);

    this.dataLength = this.chunker.read(reader);
    this.line = null;
    this.endOfLineOffset = 0;
    popFront();
  }
  @property bool empty()
  {
    return line is null;
  }
  @property auto front()
  {
    return line;
  }
  @property void popFront()
  {
    if(endOfLineOffset >= dataLength) {

      if(this.line is null) {
	//writefln("[DEBUG] LineReader.popFront no more data");
	return;
      }
      this.dataLength = this.chunker.read(reader);
      if(this.dataLength == 0) {
	this.line = null;
	//writefln("[DEBUG] LineReader.popFront no more data");
	return;
      }
      endOfLineOffset = 0;
    }

    auto startOfNextLine = endOfLineOffset;
    while(true) {
      if(chunker.buffer[endOfLineOffset] == '\n') {
	endOfLineOffset++;
	line = chunker.buffer[startOfNextLine..endOfLineOffset];
	break;
      }
      endOfLineOffset++;
      if(endOfLineOffset >= dataLength) {
	line = chunker.buffer[startOfNextLine..endOfLineOffset];
	break;
      }
    }

    //writefln("[DEBUG] LineReader.popFront '%s'", escape(line));

  }
}


auto byLine(CharReader reader, char[] buffer, BufferTooSmall tooSmall) {
  return LineReader(reader, buffer, tooSmall);
}
/*
auto byLine(File file, char[] buffer, BufferTooSmall tooSmall) {
  auto fileCharReader = FileCharReader(file);
  return LinesReader(&(fileCharReader.read), buffer, tooSmall);
}
*/

version(unittest_common) unittest
{
  mixin(scopedTest!("LineReader"));

  char[256] buffer256;

  void testLines(string data, size_t testLine = __LINE__) {
    CustomChunks customChunks;
	
    for(auto chunkSize = 1; chunkSize <= data.length; chunkSize++) {

      // Create Chunks
      string[] chunks;
      size_t offset;
      for(offset = 0; offset + chunkSize <= data.length; offset += chunkSize) {
	chunks ~= data[offset .. offset + chunkSize];
      }
      if(data.length - offset > 0) {
	chunks ~= data[offset .. $];
      }
      //writefln("ChunkSize %s Chunks %s", chunkSize, chunks);

      customChunks = CustomChunks(chunks);
      auto lineReader = LineReader(&(customChunks.read), buffer256, BufferTooSmall.throwException);

      //writefln("[DEBUG] lineReader.front = '%s'", lineReader.front);
      
      
      size_t lineNumber = 1;
      foreach(line; data.byLine()) {
	//writefln("[DEBUG] line %s '%s'", lineNumber, escape(line));

	if(lineReader.empty) {
	  writefln("Expected line '%s' but no more lines", escape(line));
	  assert(0);
	}
	if(line != lineReader.front) {
	  writefln("Expected: '%s'", escape(line));
	  writefln("Actual  : '%s'", escape(lineReader.front));
	  assert(0);
	}
	lineReader.popFront;
	lineNumber++;
      }

      if(!lineReader.empty) {
	writefln("Got extra line '%s' but expected no more lines", escape(lineReader.front));
	assert(0);
      }

    }
  }

  //testLines("abc");
  //testLines("abc\n");
  testLines("abc\n1234\n\n");


}
