module more.common;

import std.ascii;
import std.conv;
import std.range;
import std.stdio;
import std.string;

import core.exception;

import std.c.string : memmove;

void implement() {
  throw new Exception("not implemented");
}
void implement(string feature) {
  throw new Exception(feature~" not implemented");
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
void startTest(string name)
{
  writeSection(name ~ ": Start");
}
void endTest(string name)
{
  writeSection(name ~ ": Passed");
}
void writeSection(string name)
{
  writeln("----------------------------------------");
  writeln(name);
  writeln("----------------------------------------");
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


unittest
{
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
unittest
{
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

  writeSection("Line Parser Tests: Start");

  TestLineParser(LineParser([],1));
  TestLineParser(LineParser([0,0,0], 3));
  TestLineParser(LineParser(new ubyte[256]));

  writeSection("Line Parser Tests: Passed");
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

unittest
{
  import std.stdio;
  import std.array;
  import std.string;

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
   "\0"  ,
   "\x01",
   "\x02",
   "\x03",
   "\x04",
   "\x05",
   "\x06",
   "\a",  // Bell
   "\b",  // Backspace
   "\t",
   "\n",
   "\v",  // Vertical tab
   "\f",  // Form feed
   "\r",
   "\x0E",
   "\x0F",
   "\x10",
   "\x11",
   "\x12",
   "\x13",
   "\x14",
   "\x15",
   "\x16",
   "\x17",
   "\x18",
   "\x19",
   "\x1A",
   "\x1B",
   "\x1C",
   "\x1D",
   "\x1E",
   "\x1F",
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

unittest
{
  import std.stdio;
  assert (char.max == escapeTable.length - 1);

  for(auto c = ' '; c <= '~'; c++) {
    //writefln("%s == %s", c, escape(c)[0]);
    assert(c == escape(c)[0]);
  }
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

alias size_t delegate(char[] buffer) CharReader;
alias size_t delegate(ubyte[] buffer) DataReader;


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



