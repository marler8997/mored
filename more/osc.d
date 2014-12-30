/** @mainpage OSCPKT : a minimalistic OSC ( http://opensoundcontrol.org ) c++ library 

  Before using this file please take the time to read the OSC spec, it
  is short and not complicated: http://opensoundcontrol.org/spec-1_0

  Features: 
    - handles basic OSC types: TFihfdsb
    - handles bundles
    - handles OSC pattern-matching rules (wildcards etc in message paths)
    - portable on win / macos / linux
    - robust wrt malformed packets
    - optional udp transport for packets
    - concise, all in a single .h file
    - does not throw exceptions

  does not:
    - take into account timestamp values.
    - provide a cpu-scalable message dispatching.
    - not suitable for use inside a realtime thread as it allocates memory when 
    building or reading messages.


  There are basically 3 classes of interest:
    - oscpkt::Message       : read/write the content of an OSC message
    - oscpkt::PacketReader  : read the bundles/messages embedded in an OSC packet
    - oscpkt::PacketWriter  : write bundles/messages into an OSC packet

  And optionaly:
    - oscpkt::UdpSocket     : read/write OSC packets over UDP.

  @example: oscpkt_demo.cc
  @example: oscpkt_test.cc
*/

/* Copyright (C) 2010  Julien Pommier

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.

  (this is the zlib license)
*/
module more.osc;

import std.string : format;
import std.c.string : strchr,strncmp;

version(unittest)
{
  import std.stdio;
}


class OscException : Exception
{
  this(string msg)
  {
    super(msg);
  }
}

struct OscMessage
{
  const(char)[] address; // Note: that this address is null terminated

  void parse(const(ubyte)[] data)
  {
    if(data.length < 4)
      throw new OscException("an OscPacket must be at least 4 bytes long");
    if( (data.length & 0x03) != 0 )
      throw new OscException("an OscPacket length must be a multiple of 4");

    if(data[0] != '/')
      throw new OscException(format("an Osc request must start with the '/' character but it started with '%s'", data[0]));
    
    size_t checkIndex = 3;
    while(true) {
      if(data[checkIndex] == 0) break;
      checkIndex += 4;
      if(checkIndex >= data.length)
	throw new OscException("missing null character to end osc string");
    }

    do {
      if(data[checkIndex - 1] != 0) break;
      checkIndex--;
    } while(checkIndex > 0);

    this.address = cast(const(char)[])data[0..checkIndex];

    //throw new Exception("implement");
  }
  unittest
  {
    OscMessage message;

    message.parse([cast(ubyte)'/',0,0,0]);
    assert(message.address == "/");

    message.parse([cast(ubyte)'/','a',0,0]);
    assert(message.address == "/a");

    message.parse([cast(ubyte)'/','a','b',0]);
    assert(message.address == "/ab");

    message.parse([cast(ubyte)'/','a','b','c',0,0,0,0]);
    assert(message.address == "/abc");

    message.parse([cast(ubyte)'/','a','b','c','d',0,0,0]);
    assert(message.address == "/abcd");

    message.parse([cast(ubyte)'/','a','b','c','d','e',0,0]);
    assert(message.address == "/abcde");

    message.parse([cast(ubyte)'/','a','b','c','d','e','f',0]);
    assert(message.address == "/abcdef");
    
  }
}

/**
   oscLength includes the argument length and the type flag length
 */
size_t oscLength(const(ubyte)[] s)
{
  return ceil4(s.length + 1); // +1 for the terminating null
}
size_t oscLength(A...)(A args)
{
  static if(A.length == 0) {
    return 0;
  } else {
    size_t total = 0;

    foreach(arg; args) {
      static if( isSomeString!(typeof(arg)) ) {
	total += oscLength(cast(const(ubyte)[])arg);
      } else {
	total += oscLength(arg);
	//static assert(0, "oscLength function: unhandled arg type "~typeid(arg));
      }
    }

    // Add type flags ',' + A.length + '\0'
    total += ceil4(2 + A.length);
      
    return total;
  }
}
unittest
{
  assert(oscLength("")    == 8);
  assert(oscLength("a")   == 8);
  assert(oscLength("ab")  == 8);
  assert(oscLength("abc") == 8);
  assert(oscLength("abcd")    == 12);
  assert(oscLength("abcde")   == 12);
  assert(oscLength("abcdef")  == 12);
  assert(oscLength("abcdefg") == 12);
  assert(oscLength("abcdefgh") == 16);

  assert(oscLength("","a","abcd") == 24);
}

template oscTypeFlag(T)
{
  static if( isSomeString!T ) {
    enum oscTypeFlag = 's';
  } else {
    static assert(0, "oscTypeFlag: unhandled type "~typeid(T));
  }
}
size_t oscSerialize(ubyte* buffer, const(ubyte)[] s)
{
  buffer[0..s.length] = s[];
  size_t limit = s.length + nullPaddingLength(s.length);
  buffer[s.length..limit] = 0;
  return limit;
}
//
// Todo: I could templatize the buffer type to support
//       using a buffer that might need to be resized
//
auto oscSerializeArgs(bool trackLength, A...)(ubyte* buffer, A args)
{
  static if(trackLength) {
    const ubyte* originalBuffer = buffer;
  }

  static if(A.length > 0) {
    //
    // Serialize type flags
    //
    buffer[0] = ',';
    foreach(i, arg; args) {
      buffer[1+i] = oscTypeFlag!(typeof(arg));
    }

    static if( nullPaddingLength(1 + A.length) == 1) {
      buffer[1+A.length    ] = 0;
      buffer += 1 + A.length + 1;
    } else static if( nullPaddingLength(1 + A.length) == 2) {
      buffer[1+A.length    ] = 0;
      buffer[1+A.length + 1] = 0;
      buffer += 1 + A.length + 2;
    } else static if( nullPaddingLength(1 + A.length) == 3) {
      buffer[1+A.length    ] = 0;
      buffer[1+A.length + 1] = 0;
      buffer[1+A.length + 2] = 0;
      buffer += 1 + A.length + 3;
    } else static if( nullPaddingLength(1 + A.length) == 4) {
      buffer[1+A.length    ] = 0;
      buffer[1+A.length + 1] = 0;
      buffer[1+A.length + 2] = 0;
      buffer[1+A.length + 3] = 0;
      buffer += 1 + A.length + 4;
    } else {
      static assert(0, "bug");
    }

    //
    // Serialize arg values
    //
    foreach(arg; args) {
      static if( isSomeString!(typeof(arg)) ) {
	buffer += oscSerialize(buffer, cast(const(ubyte)[])arg);
      } else {
	//static assert(0, "oscSerialize function: unhandled arg type "~typeid(arg));
	buffer += oscSerialize(buffer, arg);
      }
    }

    static if(trackLength) {
      return buffer - originalBuffer;
    }
  }
}
unittest
{
  void test(A...)(ubyte[] expected, A args)
  {
    auto buffer = new ubyte[oscLength(args)];

    //assert(expected.length == buffer.length,
    //format("expected %s bytes 

    oscSerializeArgs!false(buffer.ptr, args);
    foreach(i, e; expected) {
      if(e != buffer[i]) {
	writefln("Expected: %s", expected);
	writefln("Actual  : %s", buffer);
	writefln("Expected: %s", cast(string)expected);
	writefln("Actual  : %s", cast(string)buffer);
	assert(0);
      }
    }
  }

  test(cast(ubyte[])",s\0\0abc\0", "abc");
  test(cast(ubyte[])",s\0\0abcd\0\0\0\0", "abcd");
  test(cast(ubyte[])",ss\0abc\0data\0\0\0\0", "abc", "data");
}


/**
   Peel the top-most osc container/method from the osc address. The address is null terminated and must start with a forward slash.  address will point to the next forward slash or null. '/'.
 */
inout(char)[] peel(ref inout(char)* address)
in { assert(*address == '/'); }
body
{
  auto start = address + 1;
  auto p = start;
  while(true) {
    auto c = *p;
    if(c == 0 || c == '/') {
      address = p;
      return start[0..p-start];
    }
    p++;
  }
}
unittest
{
  immutable(char)* addr;

  addr = "/\0".ptr;
  assert(peel(addr) == "");
  assert(*addr == '\0');

  addr = "//".ptr;
  assert(peel(addr) == "");
  assert(*addr == '/');

  addr = "/a\0".ptr;
  assert(peel(addr) == "a");
  assert(*addr == '\0');

  addr = "/abcd\0".ptr;
  assert(peel(addr) == "abcd");
  assert(*addr == '\0');

  addr = "/abcd/".ptr;
  assert(peel(addr) == "abcd");
  assert(*addr == '/');
}


// Invalid characters for method/container
//    32 ' '
//    35 '#'
//    42 '*'
//    44 ','
//    47 '/'
//    63 '?'
//    91 '['
//    93 ']'
//   123 '{'
//   125 '}'

/**
   Implements a tree of Osc functions in a hiearchy.  Used to 
   lookup functions via an OscAddress.
 */
struct OscMethodTree
{
  interface INode
  {
  }

  class MapNode : INode
  {
    INode[string] children;
  }

  INode root;

  void dispatch(ref OscMessage message)
  in { assert(message.address[0] == '/'); }
  body
  {
    
  }
  
}











/**
   OSC timetag stuff, the highest 32-bit are seconds, the lowest are fraction of a second.
*/
struct TimeTag {
  enum TimeTag immediate = TimeTag(1);
  
  ulong v;
/+
  TimeTag() : v(1) {}
  explicit TimeTag(uint64_t w): v(w) {}
  operator uint64_t() const { return v; }
  static TimeTag immediate() { return TimeTag(1); }+/
}

/* the various types that we handle (OSC 1.0 specifies that INT32/FLOAT/STRING/BLOB are the bare minimum) */


enum OscTypeFlag : char
{
  true_   = 'T',
  false_  = 'F', 
  int32   = 'i',
  int64   = 'h',
  float_  = 'f',
  double_ = 'd',
  string_ = 's',
  blob    = 'b',
}

enum OscType {
  true_,
  false_, 
  int32,
  int64,
  float_,
  double_,
  string_,
  blob,
};
immutable char[] typeIDs = ['T','F','i','h','f','d','s','b'];
char getID(OscType type) 
{
  return typeIDs[type];
}
unittest
{
  foreach(type; OscType.min..OscType.max) {
    //writefln("type '%s' id=%s", type, type.getID());
    type.getID(); // make sure it works
  }
}

// round to the next multiple of 4, works for size_t and pointer arguments
size_t ceil4(size_t size)
{
  return (size + 3) & ~(cast(size_t)3);
}
unittest
{
  assert(ceil4(0) == 0);

  assert(ceil4(1) == 4);
  assert(ceil4(2) == 4);
  assert(ceil4(3) == 4);
  assert(ceil4(4) == 4);

  assert(ceil4(5) == 8);
  assert(ceil4(6) == 8);
  assert(ceil4(7) == 8);
  assert(ceil4(8) == 8);
}

// returns 1-4
ubyte nullPaddingLength(size_t length) pure
{
  final switch(length & 0x03) {
  case 0: return 4;
  case 1: return 3;
  case 2: return 2;
  case 3: return 1;
  }
}


/+
// check that a memory area is zero padded until the next address which is a multiple of 4
inline bool isZeroPaddingCorrect(const char *p) {
  const char *q = ceil4(p);
  for (;p < q; ++p)
    if (*p != 0) { return false; }
  return true;
}

+/

union ValueUnion(T)
{
  int[T.sizeof] data;
  T value;
}

/** read unaligned bytes into a POD type, assuming the bytes are a little endian representation */
T oscDeserialize(T)(const(int)* data)
{
  version(BigEndian) {
    return *(cast(T*)data);
  } else {
    ValueUnion!T p;
    foreach(i; 0..T.sizeof) {
      p.data[i] = data[(T.sizeof-1) - i];
    }
    return p.value;
  }
}
/** stored a POD type into an unaligned bytes array, using little endian representation */
void oscSerialize(T)(const T value, int* bytes)
{
  version(BigEndian) {
    bytes[0..T.sizeof] = (cast(int*)&value)[0..T.sizeof];
  } else {
    int* p = cast(int*)&value;
    foreach(i; 0..T.sizeof) {
      bytes[i] = p[(T.sizeof-1) - i];
    }
  }
}

unittest
{
  int[16] b;

  oscSerialize!int(3, b.ptr);
  //writefln("%s", b);
  assert(3 == oscDeserialize!int(b.ptr));

  b[0] = 3;
  assert(3 == oscDeserialize!int(b.ptr));
}

// see the OSC spec for the precise pattern matching rules
const(char)* internalPatternMatch(const(char) *pattern, const(char) *path) {
  while (*pattern) {
    const(char) *p = pattern;
    if (*p == '?' && *path) { ++p; ++path; }
    else if (*p == '[' && *path) { // bracketted range, e.g. [a-zABC]
      ++p;
      bool reverse = false;
      if (*p == '!') {
	//debug writefln("[DEBUG] enter reversed bracket");
	reverse = true; ++p;
      } else {
	//debug writefln("[DEBUG] enter bracket");
      }
      bool match = reverse;
      for (; *p && *p != ']'; ++p) {
        char c0 = *p, c1 = c0;
        if (p[1] == '-' && p[2] && p[2] != ']') { p += 2; c1 = *p; }
        if (*path >= c0 && *path <= c1) { match = !reverse; }
      }
      if (!match || *p != ']') return pattern;
      ++p; ++path;
    } else if (*p == '*') { // wildcard '*'
      while (*p == '*') ++p; 
      const(char)* best = null;
      while (true) {
        const char *ret = internalPatternMatch(p, path);
        if (ret && ret > best) best = ret;
        if (*path == 0 || *path == '/') break;
        else ++path;
      }
      return best;
    } else if (*p == '/' && *(p+1) == '/') { // the super-wildcard '//'
      while (*(p+1)=='/') ++p;
      const(char)* best = null;
      while (true) {
        const char *ret = internalPatternMatch(p, path);
        if (ret && ret > best) best = ret;
        if (*path == 0) break;
        if (*path == 0 || (path = strchr(path+1, '/')) == null) break;
      }      
      return best;
    } else if (*p == '{') { // braced list {foo,bar,baz}
      const(char)* end = strchr(p, '}'), q;
      if (!end) return null; // syntax error in brace list..
      bool match = false;
      do {
        ++p;
        q = strchr(p, ',');
        if (q == null || q > end) q = end;
        if (strncmp(p, path, q-p) == 0) {
          path += (q-p); p = end+1; match = true;
        } else p=q;
      } while (q != end && !match);
      if (!match) return pattern;
    } else if (*p == *path) { ++p; ++path; } // any other character
    else break;
    pattern = p;
  }
  return (*path == 0 ? pattern : null);
}

/** check if the path matches the supplied path pattern , according to the OSC spec pattern 
    rules ('*' and '//' wildcards, '{}' alternatives, brackets etc) */
bool fullPatternMatch(const(char)[] pattern, const(char)[] test)
{
  //debug writefln("[DEBUG] pattern '%s' match '%s'", pattern, test);
  auto q = internalPatternMatch(pattern.ptr, test.ptr);
  return q && *q == 0;
}
/** check if the path matches the beginning of pattern */
bool partialPatternMatch(const(char)[] pattern, const(char)[] test)
{
  auto q = internalPatternMatch(pattern.ptr, test.ptr);
  return q != null;
}

unittest
{
  char[16] buffer;

  assert(fullPatternMatch("", ""));
  assert(fullPatternMatch("ab12", "ab12"));

  foreach(char c; 1..255) {
    buffer[0] = c;
    buffer[1] = '\0';
    assert(fullPatternMatch("?", buffer));
    buffer[0] = 'a';
    buffer[1] = c;
    buffer[2] = 'c';
    buffer[3] = '\0';
    assert(fullPatternMatch("a?c", buffer));
  }

  // Test wildcard '*'
  assert(fullPatternMatch("*", ""));
  assert(fullPatternMatch("*", "1"));
  assert(fullPatternMatch("*", "abcd"));
  assert(fullPatternMatch("/*", "/info"));
  assert(fullPatternMatch("*/", "info/"));
  assert(fullPatternMatch("*/*", "info/specific"));

  // Test bracket []
  assert(fullPatternMatch("[ab]", "a"));
  assert(fullPatternMatch("[ab]", "b"));
  // Test bracket [] with dash '-'
  assert(fullPatternMatch("[-]", "-"));
  assert(fullPatternMatch("[a-]", "a"));
  assert(fullPatternMatch("[a-]", "-"));
  assert(fullPatternMatch("[a-c]", "a"));
  assert(fullPatternMatch("[a-c]", "b"));
  assert(fullPatternMatch("[a-c]", "c"));
  foreach(c; 'a'..'z') {
    buffer[0] = c;
    buffer[1] = '\0';
    assert(fullPatternMatch("[a-z]", buffer));
  }
  // Test [!c]
  buffer[1] = 0;
  foreach(char not; 1..255) {
    if(not == ']') continue;
    auto pattern = "[!"~not~"]\0";
    buffer[0] = not;
    assert(!fullPatternMatch(pattern, buffer));

    foreach(char c; 1..255) {
      if(c == not) continue;
      buffer[0] = c;
      assert(fullPatternMatch(pattern, buffer));
    }
  }
  // Test [!min-max]
  foreach(char c; 1..255) {
    if(c >= 'a' && c <= 'z') continue;
    buffer[0] = c;
    buffer[1] = '\0';
    assert(fullPatternMatch("[!a-z]", buffer));
  }

  // Test brace expression
  assert(fullPatternMatch("{abc}", "abc"));
  assert(fullPatternMatch("{abc,123}", "abc"));
  assert(fullPatternMatch("{abc,123}", "123"));
}

/+
/** internal stuff, handles the dynamic storage with correct alignments to 4 bytes */
struct Storage {
  char[] buffer;
  this(char[] buffer)
  {
    this.buffer = buffer;
  }
  char *getBytes(size_t sz) {
    assert((data.size() & 3) == 0);
    if (data.size() + sz > data.capacity()) { data.reserve((data.size() + sz)*2); }
    size_t sz4 = ceil4(sz);
    size_t pos = data.size(); 
    data.resize(pos + sz4); // resize will fill with zeros, so the zero padding is OK
    return &(data[pos]);
  }
  char *begin() { return data.size() ? &data.front() : 0; }
  char *end() { return begin() + size(); }
  const char *begin() const { return data.size() ? &data.front() : 0; }
  const char *end() const { return begin() + size(); }
  size_t size() const { return data.size(); }
  void assign(const char *beg, const char *end) { data.assign(beg, end); }
  void clear() { data.resize(0); }
};
+/
/+
#if defined(OSCPKT_DEBUG)
#define OSCPKT_SET_ERR(errcode) do { if (!err) { err = errcode; std::cerr << "set " #errcode << " at line " << __LINE__ << "\n"; } } while (0)
#else
#define OSCPKT_SET_ERR(errcode) do { if (!err) err = errcode; } while (0)
#endif
+/
enum ErrorCode {
  ok,
  // errors raised by the Message class:
  malformedAddressPattern, malformedTypeTags, malformedArguments, unhandledTypeTags,
  // errors raised by ArgReader
  typeMismatch, notEnoughArgs, patternMismatch,
  // errors raised by PacketReader/PacketWriter
  invalidBundle, invalidPacketSize, bundleRequiredForMultiMessages,
}


struct ArgumentStorage
{
  int[] int32Data;
}



struct OscArg
{
  size_t int32Offset;
  size_t int32Length;
}

/**
   struct used to hold an OSC message that will be written or read.

   The list of arguments is exposed as a sort of queue. You "pop"
   arguments from the front of the queue when reading, you push
   arguments at the back of the queue when writing.

   Many functions return *this, so they can be chained: init("/foo").pushInt32(2).pushStr("kllk")...

   Example of use:

   creation of a message:
   @code
   msg.init("/foo").pushInt32(4).pushStr("bar");
   @endcode
   reading a message, with error detection:
   @code
   if (msg.match("/foo/b*ar/plop")) {
     int i; std::string s; std::vector<char> b;
     if (msg.arg().popInt32(i).popStr(s).popBlob(b).isOkNoMoreArgs()) {
       process message...;
     } else arguments mismatch;
   }
   @endcode
*/
class Message {
  TimeTag timeTag;
  string address;
  string typeTags;
  //OscArg[] arguments; // array of pairs (offset,length), offset being an index into the 'storage' array.
  //Storage storage; // the arguments data is stored here
  ArgumentStorage storage;
  
  ErrorCode error;

  /** ArgReader is used for popping arguments from a Message, holds a
      pointer to the original Message, and maintains a local error code */
  class ArgReader {
    const Message *msg;
    ErrorCode error;
    size_t argIndex; // arg index of the next arg that will be popped out.
    size_t argInt32Offset; // The offset of the current arg in the int32 buffer

    this(const Message* msg, ErrorCode error = ErrorCode.ok)
    in { assert(msg != null); }
    body
    {
      this.msg = msg;
      this.error = (error != ErrorCode.ok) ? error : msg.error;
    }

/+
    OscType currentTypeTag()
    in { argIndex < msg.typeTags.length)
    body {
      return msg.typeTags[argIndex];
    }
+/

    // returns 0 on error, otherwise the type char
    char tryCurrentTypeChar() const
    {
      return (argIndex < msg.typeTags.length) ? msg.typeTags[argIndex] : 0;
    }

    bool isBool() const { auto c = tryCurrentTypeChar(); return c == OscTypeFlag.true_ || c == OscTypeFlag.false_; }
    bool isInt32() const { return tryCurrentTypeChar() == OscTypeFlag.int32; }
    bool isInt64() const { return tryCurrentTypeChar() == OscTypeFlag.int64; }
    bool isFloat() const { return tryCurrentTypeChar() == OscTypeFlag.float_; }
    bool isDouble() const { return tryCurrentTypeChar() == OscTypeFlag.double_; }
    bool isStr() const { return tryCurrentTypeChar() == OscTypeFlag.string_; }
    bool isBlob() const { return tryCurrentTypeChar() == OscTypeFlag.blob; }

    size_t argsLeft() const { return msg.typeTags.length - argIndex; }
    bool isOk() const { return error == ErrorCode.ok; }

    /** call this at the end of the popXXX() chain to make sure everything is ok and 
        all arguments have been popped */
    bool enforceDone() const { return error == ErrorCode.ok && argsLeft() == 0; }

    T pop(T)(OscTypeTag tag)
    {
      if(argIndex >= msg.typeTags.length)
	throw new Exception("There are no more arguments");
      if(tag != tryCurrentTypeChar())
	throw new Exception(format("Expected type '%s' but current type is '%s'", tag, tryCurrentTypeChar()));
      return oscDeserialize!T(msg.storage.bytes.ptr + msg.storage.int32Data[argInt32Offset]);
    }
/+
    /** retrieve an int32 argument */
    int popInt32() { return popPod<int32_t>(OscTypeFlag.int32, i); }
    /** retrieve an int64 argument */
    ArgReader &popInt64(int64_t &i) { return popPod<int64_t>(OscTypeFlag.int64, i); }
    /** retrieve a single precision floating point argument */
    ArgReader &popFloat(float &f) { return popPod<float>(OscTypeFlag.float_, f); }
    /** retrieve a double precision floating point argument */
    ArgReader &popDouble(double &d) { return popPod<double>(OscTypeFlag.double_, d); }
    /** retrieve a string argument (no check performed on its content, so it may contain any byte value except 0) */
    ArgReader &popStr(std::string &s) {
      if (precheck(OscTypeFlag.string_)) {
        s = argBeg(argIndex++);
      }
      return *this;
    }
    /** retrieve a binary blob */
    ArgReader &popBlob(std::vector<char> &b) { 
      if (precheck(OscTypeFlag.blob)) {
        b.assign(argBeg(argIndex)+4, argEnd(argIndex)); 
        ++argIndex;
      }
      return *this;
    }
    /** retrieve a boolean argument */
    ArgReader &popBool(bool &b) {
      b = false;
      if (argIndex >= msg->arguments.size()) OSCPKT_SET_ERR(NOT_ENOUGH_ARG); 
      else if (tryCurrentTypeChar() == OscTypeFlag.true_) b = true;
      else if (tryCurrentTypeChar() == OscTypeFlag.false_) b = false;
      else OSCPKT_SET_ERR(TYPE_MISMATCH);
      ++argIndex;
      return *this;
    }
    /** skip whatever comes next */
    ArgReader &pop() {
      if (argIndex >= msg->arguments.size()) OSCPKT_SET_ERR(NOT_ENOUGH_ARG); 
      else ++argIndex;
      return *this;
    }
  private:
+/
/+
    auto argBeg(size_t argIndex) {
      if (error || idx >= msg->arguments.size()) return 0; 
      else return msg->storage.begin() + msg->arguments[idx].first;
    }
+/
/+
    const char *argEnd(size_t idx) {
      if (error || idx >= msg->arguments.size()) return 0; 
      else return msg->storage.begin() + msg->arguments[idx].first + msg->arguments[idx].second;
    }
+/

/+
    /* pre-check stuff before popping an argument from the message */
    private bool precheck(int tag) { 
      if (argIndex >= msg->arguments.size()) OSCPKT_SET_ERR(NOT_ENOUGH_ARG); 
      else if (!error && tryCurrentTypeChar() != tag) OSCPKT_SET_ERR(TYPE_MISMATCH);
      return error == ErrorCode.ok;
    }
+/
  };

  //this() { clear(); }
  this(string address, TimeTag timeTag = TimeTag.immediate)
  {
    this.address = address;
    this.timeTag = timeTag;
    this.error = ErrorCode.ok;
  }
/+
  this(const void *ptr, size_t sz, TimeTag timeTag = TimeTag.immediate)
  {
    buildFromRawData(ptr, sz); timeTag = tt;
  }
+/
  bool isOk() const { return error == ErrorCode.ok; }
  ErrorCode getError() const { return error; }

  /** return the typeTags string, with its initial ',' stripped. */
  //string typeTags() const { return typeTags; }

  /** retrieve the address pattern. If you want to follow to the whole OSC spec, you
      have to handle its matching rules for address specifications -- this file does 
      not provide this functionality */
  //string addressPattern() const { return address; }
  //TimeTag timeTag() const { return timeTag; }

  /** reset the message to a clean state */
  void clear()
  {
    address = null;
    typeTags = null;
    //storage.clear();
    //arguments = null;
    error = ErrorCode.ok;
    timeTag = TimeTag.immediate;
  }

  /** clear the message and start a new message with the supplied address and timeTag. */
  void init(string address, TimeTag timeTag = TimeTag.immediate)
  in { assert(address.length > 0 && address[0] == '/'); }
  body {
    clear();
    this.address = address;
    this.timeTag = timeTag;
  }

/+
  /** start a matching test. The typical use-case is to follow this by
      a sequence of calls to popXXX() and a final call to
      enforceDone() which will allow to check that everything went
      fine. For example:
      @code
      if (msg.match("/foo").popInt32(i).enforceDone()) { blah(i); } 
      else if (msg.match("/bar").popStr(s).popInt32(i).enforceDone()) { plop(s,i); }
      else cerr << "unhandled message: " << msg << "\n";
      @endcode
  */
  ArgReader match(const std::string &test) const {
    return ArgReader(*this, fullPatternMatch(address.c_str(), test.c_str()) ? ErrorCode.ok : PATTERN_MISMATCH);
  }
  /** return true if the 'test' path matched by the first characters of addressPattern().
      For ex. ("/foo/bar").partialMatch("/foo/") is true */
  ArgReader partialMatch(const std::string &test) const {
    return ArgReader(*this, partialPatternMatch(address.c_str(), test.c_str()) ? ErrorCode.ok : PATTERN_MISMATCH);
  }
  ArgReader arg() const { return ArgReader(*this, ErrorCode.ok); }

  /** build the osc message for raw data (the message will keep a copy of that data) */
  void buildFromRawData(const void *ptr, size_t sz) {
    clear();
    storage.assign((const char*)ptr, (const char*)ptr + sz);
    const char *address_beg = storage.begin();
    const char *address_end = (const char*)memchr(address_beg, 0, storage.end()-address_beg);
    if (!address_end || !isZeroPaddingCorrect(address_end+1) || address_beg[0] != '/') { 
      OSCPKT_SET_ERROR(MALFORMED_ADDRESS_PATTERN); return; 
    } else address.assign(address_beg, address_end);

    const char *typeTags_beg = ceil4(address_end+1);
    const char *typeTags_end = (const char*)memchr(typeTags_beg, 0, storage.end()-typeTags_beg);
    if (!typeTags_end || !isZeroPaddingCorrect(typeTags_end+1) || typeTags_beg[0] != ',') { 
      OSCPKT_SET_ERROR(MALFORMED_TYPETAGS); return; 
    } else typeTags.assign(typeTags_beg+1, typeTags_end); // we do not copy the initial ','

    const char *arg = ceil4(typeTags_end+1); assert(arg <= storage.end()); 
    size_t iarg = 0;
    while (isOk() && iarg < typeTags.size()) {
      assert(arg <= storage.end()); 
      size_t len = getArgSize(typeTags[iarg], arg);
      if (isOk()) arguments.push_back(std::make_pair(arg - storage.begin(), len));
      arg += ceil4(len); ++iarg;
    }
    if (iarg < typeTags.size() || arg != storage.end()) {
      OSCPKT_SET_ERR(MALFORMED_ARGUMENTS);
    }
  }

  /* below are all the functions that serve when *writing* a message */
  Message &pushBool(bool b) { 
    typeTags += (b ? OscTypeFlag.true_ : OscTypeFlag.false_); 
    arguments.push_back(std::make_pair(storage.size(), storage.size()));
    return *this;
  }
  Message &pushInt32(int32_t i) { return pushPod(OscTypeFlag.int32, i); }
  Message &pushInt64(int64_t h) { return pushPod(OscTypeFlag.int64, h); }
  Message &pushFloat(float f) { return pushPod(OscTypeFlag.float_, f); }
  Message &pushDouble(double d) { return pushPod(OscTypeFlag.double_, d); }
  Message &pushStr(const std::string &s) {
    assert(s.size() < 2147483647); // insane values are not welcome
    typeTags += OscTypeFlag.string_;
    arguments.push_back(std::make_pair(storage.size(), s.size() + 1));
    strcpy(storage.getBytes(s.size()+1), s.c_str());
    return *this;
  }
  Message &pushBlob(void *ptr, size_t num_bytes) {
    assert(num_bytes < 2147483647); // insane values are not welcome
    typeTags += OscTypeFlag.blob; 
    arguments.push_back(std::make_pair(storage.size(), num_bytes+4));
    oscSerialize<int32_t>((int32_t)num_bytes, storage.getBytes(4));
    if (num_bytes)
      memcpy(storage.getBytes(num_bytes), ptr, num_bytes);
    return *this;
  }


  /** write the raw message data (used by PacketWriter) */
  void packMessage(Storage &s, bool write_size) const {
    if (!isOk()) return;
    size_t l_addr = address.size()+1, l_type = typeTags.size()+2;
    if (write_size) 
      oscSerialize<uint32_t>(uint32_t(ceil4(l_addr) + ceil4(l_type) + ceil4(storage.size())), s.getBytes(4));
    strcpy(s.getBytes(l_addr), address.c_str());
    strcpy(s.getBytes(l_type), ("," + typeTags).c_str());
    if (storage.size())
      memcpy(s.getBytes(storage.size()), const_cast<Storage&>(storage).begin(), storage.size());
  }

private:

  /* get the number of bytes occupied by the argument */
  size_t getArgSize(int type, const char *p) {
    if (error) return 0;
    size_t sz = 0;
    assert(p >= storage.begin() && p <= storage.end());
    switch (type) {
      case OscTypeFlag.true_:
      case OscTypeFlag.false_: sz = 0; break;
      case OscTypeFlag.int32: 
      case OscTypeFlag.float_: sz = 4; break;
      case OscTypeFlag.int64: 
      case OscTypeFlag.double_: sz = 8; break;
      case OscTypeFlag.string_: {
        const char *q = (const char*)memchr(p, 0, storage.end()-p);
        if (!q) OSCPKT_SET_ERR(MALFORMED_ARGUMENTS);
        else sz = (q-p)+1;
      } break;
      case OscTypeFlag.blob: {
        if (p == storage.end()) { OSCPKT_SET_ERR(MALFORMED_ARGUMENTS); return 0; }
        sz = 4+oscDeserialize<uint32_t>(p);
      } break;
      default: {
        OSCPKT_SET_ERR(UNHANDLED_TYPE_TAGS); return 0;
      } break;
    }
    if (p+sz > storage.end() || /* string or blob too large.. */
        p+sz < p /* or even blob so large that it did overflow */) { 
      OSCPKT_SET_ERR(MALFORMED_ARGUMENTS); return 0; 
    }
    if (!isZeroPaddingCorrect(p+sz)) { OSCPKT_SET_ERR(MALFORMED_ARGUMENTS); return 0; }
    return sz;
  }

  template <typename POD> Message &pushPod(int tag, POD v) {
    typeTags += (char)tag; 
    arguments.push_back(std::make_pair(storage.size(), sizeof(POD)));
    oscSerialize(v, storage.getBytes(sizeof(POD))); 
    return *this;
  }

#ifdef OSCPKT_OSTREAM_OUTPUT
  friend std::ostream &operator<<(std::ostream &os, const Message &msg) {
    os << "osc_address: '" << msg.address << "', types: '" << msg.typeTags << "', timetag=" << msg.timeTag << ", args=[";
    Message::ArgReader arg(msg);
    while (arg.argsLeft() && arg.isOk()) {
      if (arg.isBool()) { bool b; arg.popBool(b); os << (b?"True":"False"); }
      else if (arg.isInt32()) { int32_t i; arg.popInt32(i); os << i; }
      else if (arg.isInt64()) { int64_t h; arg.popInt64(h); os << h << "ll"; }
      else if (arg.isFloat()) { float f; arg.popFloat(f); os << f << "f"; }
      else if (arg.isDouble()) { double d; arg.popDouble(d); os << d; }
      else if (arg.isStr()) { std::string s; arg.popStr(s); os << "'" << s << "'"; }
      else if (arg.isBlob()) { std::vector<char> b; arg.popBlob(b); os << "Blob " << b.size() << " bytes"; }
      else {
        assert(0); // I forgot a case..
      }
      if (arg.argsLeft()) os << ", ";
    }
    if (!arg.isOk()) { os << " ERROR#" << arg.getError(); }
    os << "]";
    return os;
  }
#endif
+/

};
/+
/**
   parse an OSC packet and extracts the embedded OSC messages. 
*/
class PacketReader {
public:
  PacketReader() { error = ErrorCode.ok; }
  /** pointer and size of the osc packet to be parsed. */
  PacketReader(const void *ptr, size_t sz) { init(ptr, sz); }

  void init(const void *ptr, size_t sz) {
    error = ErrorCode.ok; messages.clear();
    if ((sz%4) == 0) { 
      parse((const char*)ptr, (const char *)ptr+sz, TimeTag::immediate());
    } else OSCPKT_SET_ERR(INVALID_PACKET_SIZE);
    it_messages = messages.begin();
  }
  
  /** extract the next osc message from the packet. return 0 when all messages have been read, or in case of error. */
  Message *popMessage() {
    if (!error && !messages.empty() && it_messages != messages.end()) return &*it_messages++;
    else return 0;
  }
  bool isOk() const { return error == ErrorCode.ok; }
  ErrorCode getError() const { return error; }

private:
  std::list<Message> messages;
  std::list<Message>::iterator it_messages;
  ErrorCode error;
  
  void parse(const char *beg, const char *end, TimeTag timeTag) {
    assert(beg <= end && !error); assert(((end-beg)%4)==0);
    
    if (beg == end) return;
    if (*beg == '#') {
      /* it's a bundle */
      if (end - beg >= 20 
          && memcmp(beg, "#bundle\0", 8) == 0) {
        TimeTag timeTag2(oscDeserialize<uint64_t>(beg+8));
        const char *pos = beg + 16;
        do {
          uint32_t sz = oscDeserialize<uint32_t>(pos); pos += 4;
          if ((sz&3) != 0 || pos + sz > end || pos+sz < pos) {
            OSCPKT_SET_ERR(INVALID_BUNDLE);
          } else {
            parse(pos, pos+sz, timeTag2);
            pos += sz;
          }
        } while (!error && pos != end);
      } else {
        OSCPKT_SET_ERR(INVALID_BUNDLE);
      }
    } else {
      messages.push_back(Message(beg, end-beg, timeTag));
      if (!messages.back().isOk()) OSCPKT_SET_ERR(messages.back().getError());
    }
  }
};


/**
   Assemble messages into an OSC packet. Example of use:
   @code
   PacketWriter pkt; 
   Message msg;
   pkt.startBundle(); 
   pkt.addMessage(msg.init("/foo").pushBool(true).pushStr("plop").pushFloat(3.14f));
   pkt.addMessage(msg.init("/bar").pushBool(false));
   pkt.endBundle();
   if (pkt.isOk()) {
     send(pkt.data(), pkt.size());
   }
   @endcode
*/
class PacketWriter {
public:
  PacketWriter() { init(); }
  PacketWriter &init() { err = ErrorCode.ok; storage.clear(); bundles.clear(); return *this; }
  
  /** begin a new bundle. If you plan to pack more than one message in the Osc packet, you have to 
      put them in a bundle. Nested bundles inside bundles are also allowed. */
  PacketWriter &startBundle(TimeTag ts = TimeTag::immediate()) {
    char *p;
    if (bundles.size()) p = storage.getBytes(4); // hold the bundle size
    p = storage.getBytes(8); strcpy(p, "#bundle"); bundles.push_back(p - storage.begin());
    p = storage.getBytes(8); oscSerialize<uint64_t>(ts, p);
    return *this;
  }
  /** close the current bundle. */
  PacketWriter &endBundle() {
    if (bundles.size()) {
      if (storage.size() - bundles.back() == 16) {
        oscSerialize<uint32_t>(0, storage.getBytes(4)); // the 'empty bundle' case, not very elegant
      }
      if (bundles.size()>1) { // no size stored for the top-level bundle
        oscSerialize<uint32_t>(uint32_t(storage.size() - bundles.back()), storage.begin() + bundles.back()-4);
      }
      bundles.pop_back();      
    } else OSCPKT_SET_ERR(INVALID_BUNDLE);
    return *this;
  }

  /** insert an Osc message into the current bundle / packet.
   */
  PacketWriter &addMessage(const Message &msg) {
    if (storage.size() != 0 && bundles.empty()) OSCPKT_SET_ERR(BUNDLE_REQUIRED_FOR_MULTI_MESSAGES);
    else msg.packMessage(storage, bundles.size()>0);
    if (!msg.isOk()) OSCPKT_SET_ERR(msg.getError());
    return *this;
  }

  /** the error flag will be raised if an opened bundle is not closed, or if more than one message is
      inserted in the packet without a bundle */
  bool isOk() { return err == ErrorCode.ok; }
  ErrorCode getError() { return err; }

  /** return the number of bytes of the osc packet -- will always be a
      multiple of 4 -- returns 0 if the construction of the packet has
      failed. */
  uint32_t packetSize() { return err ? 0 : (uint32_t)storage.size(); }
  
  /** return the bytes of the osc packet (NULL if the construction of the packet has failed) */
  char *packetData() { return err ? 0 : storage.begin(); }
private:  
  std::vector<size_t> bundles; // hold the position in the storage array of the beginning marker of each bundle
  Storage storage;
  ErrorCode err;
};


} // namespace oscpkt

#endif // OSCPKT_HH
+/
