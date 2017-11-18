module more.cgi;

import core.stdc.string : strlen, strcpy, memmove;
import core.time : MonoTime, Duration;
import core.stdc.stdlib : alloca;

import std.stdio : File, stdout, stderr, stdin;
import std.format : format, sformat;
import std.string : startsWith, indexOf;
import std.conv : text, to;
import std.traits : hasMember;
import std.typecons : tuple;
import std.random : Random;
import std.exception : ErrnoException;

import more.parse : hexValue, findCharPtr;
import more.format : formatEscapeByPolicy, formatEscapeSet, asciiFormatEscaped;
public import more.format : formatHex;
public import more.uri : uriDecode;

void log(T...)(const(char)[] fmt, T args)
{
    static if(T.length == 0)
    {
        stderr.writeln(fmt);
    }
    else
    {
        stderr.writefln(fmt, args);
    }
}

enum ResponseState
{
    headers, content
}
__gshared ResponseState responseState = ResponseState.headers;
void ensureResponseFinished()
{
    if(responseState == ResponseState.headers) {
        finishHeaders();
    }
}

void assertInHeaders(string functionName)
{
    if(responseState != ResponseState.headers)
    {
        log("Error: function \"%s\" was called after headers were finished", functionName);
        assert(0, "function \"" ~ functionName ~ "\" was called after headers were finished");
    }
}
void assertInContent(string functionName)
{
    version(unittest)
    {
        return;
    }
    if(responseState != ResponseState.content)
    {
        log("Error: function \"%s\" was called before headers were finished", functionName);
        assert(0, "function \"" ~ functionName ~ "\" was called before headers were finished");
    }
}

@property bool inHeaderState() { return responseState == ResponseState.headers; }
void addHeader(const(char)[] name, const(char)[] value)
{
    assertInHeaders("addHeader");
    stdout.writef("%s: %s\n", name, value);
}
void addSetCookieHeader(const(char)[] name, const(char)[] value, Duration expireTimeFromNow = Duration.zero)
{
    assertInHeaders("addSetCookieHeader");
    if(expireTimeFromNow == Duration.zero) {
        stdout.writef("Set-Cookie: %s=%s\n", name, value);
    } else {
        assert(0, "not implemented");
    }
}
void addUnsetCookieHeader(const(char)[] name)
{
    assertInHeaders("addUnsetCookieHeader");
    stdout.writef("Set-Cookie: %s=; expires=Thu, 01 Jan 1970 00:00:00 GMT\n", name);
}
void finishHeaders()
{
    assertInHeaders("finishHeaders");
    stdout.write("\n");
    responseState = ResponseState.content;
}

// writes a string or formatted string to stdout
void write(T...)(const(char)[] fmt, T args)
{
    assertInContent("write");
    static if(T.length == 0) {
        stdout.write(fmt);
    } else {
        stdout.writef(fmt, args);
    }
}
// with an appended '\n' character, writes a string or formatted
// string to stdout
void writeln(T...)(const(char)[] fmt, T args)
{
    assertInContent("writeln");
    static if(T.length == 0) {
        stdout.writeln(fmt);
    } else {
        stdout.writefln(fmt, args);
    }
}
// writes a list of values to stdout
void listWrite(T...)(T args)
{
    assertInContent("listWrite");
    stdout.write(args);
}
// with an appended '\n' character, writes a list of values to stdout
void listWriteln(T...)(T args)
{
    assertInContent("listWriteln");
    stdout.writeln(args);
}
unittest
{
    // just instantiate the templates
    // all of the following should print "Hello, World!\n"
    write("Hello");
    write(", World!\n");
    write("Hello%s", ", World!\n");
    writeln("Hello, World!");
    writeln("Hello%s", ", World!");
    listWrite("Hello", ", Wo", "rld!\n");
    listWriteln("Hel", "lo, Wo", "rld!");
}

void writeFile(const(char)[] filename)
{
    assertInContent("writeFile");
    auto file = File(filename, "rb");
    scope(exit) file.close();

    enum MAX_BUFFER_SIZE = 8192;
    auto fileSize = file.size();
    auto bufferSize = (fileSize > MAX_BUFFER_SIZE) ? MAX_BUFFER_SIZE : cast(size_t) fileSize;
    auto buffer = new char[bufferSize];
    auto fileLeft = fileSize;
    for(;fileLeft > 0;)
    {
        auto nextReadSize = (fileLeft > bufferSize) ? bufferSize : cast(size_t)fileLeft;
        auto readSize = file.rawRead(buffer).length;
        if(readSize == 0)
        {
            auto message = format("only read %s bytes out of %s byte file \"%s\"", fileSize - fileLeft, fileSize, filename);
            log("Error: %s", message);
            assert(0, message);
        }
        stdout.rawWrite(buffer[0..readSize]);
        fileLeft -= readSize;
    }
}

auto dupzstring(T)(T[] str)
{
    auto result = str.ptr[0..str.length + 1].dup;
    return result[0..$-1];
}

version(Windows)
{
    struct EnvPairString
    {
        private const(char)[] pair;
        //@property const(char)* ptr() { return pair.ptr; }
        auto asDString() { return pair; }
    }
    import core.sys.windows.windows : GetLastError, GetEnvironmentStringsA, FreeEnvironmentStringsA;
    private struct EnvPairStringsRange
    {
        const(char)* environmentStrings;
        EnvPairString current;
        this(const(char)* environmentStrings)
        {
            this.environmentStrings = environmentStrings;
            this.current.pair = environmentStrings[0..strlen(environmentStrings)];
        }
        @property bool empty() { return current.pair.ptr == null; }
        auto front() { return current; }
        void popFront()
        {
            auto nextPtr = current.pair.ptr + current.pair.length + 1;
            if(*nextPtr == '\0')
            {
                current.pair = null;
                assert(FreeEnvironmentStringsA(cast(char*)environmentStrings));
            }
            else
            {
                current.pair = nextPtr[0..strlen(nextPtr)];
            }
        }
    }
    auto envPairStrings()
    {
        auto environmentStrings = GetEnvironmentStringsA();
        assert(environmentStrings, format("GetEnvironmentStringsA failed (e=%s)", GetLastError()));
        return EnvPairStringsRange(environmentStrings);
    }
    struct EnvPair
    {
        private const(char)[] name;
        private const(char)[] value;
        @property const(char)[] tempName() { return name; }
        @property const(char)[] tempValue() { return value; }
        @property char[] permanentValue() { return value.dupzstring; }
    }
    auto envPairs()
    {
        struct Range
        {
            EnvPairStringsRange range;
            @property bool empty() { return range.empty(); }
            auto front()
            {
                auto pairString = range.front();
                auto nameLimit = pairString.pair.ptr.findCharPtr('=');
                auto nameLimitIndex = nameLimit - pairString.pair.ptr;
                auto valueStartIndex = nameLimitIndex + ( (*nameLimit == '=') ? 1 : 0);

                return EnvPair(pairString.pair[       0        .. nameLimitIndex],
                               pairString.pair[valueStartIndex ..      $        ]);
            }
            void popFront()
            {
                range.popFront();
            }
        }
        return Range(envPairStrings());
    }
}
else
{
    struct EnvPairString
    {
        private char* pair;
        //@property const(char)* ptr() { return pair; }
        auto asDString() { return pair[0..strlen(pair)]; }
    }

    extern(C) extern __gshared char** environ;
    private struct EnvPairStringsRange
    {
        EnvPairString* next;
        @property bool empty() { return next.pair is null; }
        auto front() { return *next; }
        void popFront()
        {
            next++;
        }
    }
    auto envPairStrings()
    {
        return EnvPairStringsRange(cast(EnvPairString*)environ);
    }
    struct EnvPair
    {
        private char[] name;
        private char[] value;
        @property char[] tempName() { return name; }
        @property char[] tempValue() { return value; }
        @property char[] permanentValue() { return value; }
    }
    auto envPairs()
    {
        struct Range
        {
            EnvPairStringsRange range;
            @property bool empty() { return range.empty(); }
            auto front()
            {
                auto pairString = range.front();
                auto nameLimit = pairString.pair.findCharPtr('=');
                auto nameLimitIndex = nameLimit - pairString.pair;
                auto valueStart = nameLimit + ( (*nameLimit == '=') ? 1 : 0);

                return EnvPair(pairString.pair[       0        .. nameLimitIndex],
                               valueStart[0..strlen(valueStart)]);
            }
            void popFront()
            {
                range.popFront();
            }
        }
        return Range(envPairStrings());
    }
}

auto cookieRange(T)(T* cookieString)
{
    struct Cookie
    {
        T[] name;
        T[] value;
    }
    struct Range
    {
        Cookie cookie;
        T* next;
        this(T* next)
        {
            this.next = next;
            popFront();
        }
        @property bool empty() { return cookie.name is null; }
        auto front() { return cookie; }
        void popFront()
        {
            //log("cookieRange.popFront (\"%s\")", next[0..strlen(next)]);
            next = skipCharSet!" ;"(next);
            if(*next == '\0') {
                cookie.name = null;
                //log("cookieRange.popFront return null");
                return;
            }

            auto namePtr = next;
            auto valuePtr = findCharPtr(next, '=');
            cookie.name = namePtr[0..valuePtr - namePtr];
            trimRight(&cookie.name);
            if(*valuePtr == '=') {
                valuePtr++;
                next = findCharPtr(next, ';');
                cookie.value = valuePtr[0..next - valuePtr];
                trimRight(&cookie.value);
            } else {
                cookie.value = valuePtr[0..0];
                next = valuePtr;
            }
            //log("cookieRange.popFront name=\"%s\" value=\"%s\"", cookie.name, cookie.value);
        }
    }
    return Range(cookieString);
}

auto queryVarsRange(T)(T* varZString)
{
    struct Var
    {
        T[] name;
        T[] value;
    }
    struct Range
    {
        Var var;
        T* next;
        this(T* varZString)
        {
            this.next = varZString;
            popFront();
        }
        @property bool empty() { return var.name is null; }
        auto front() { return var; }
        void popFront()
        {
            next = skipCharSet!"&"(next);

            if(*next == '\0') {
                var.name = null;
            } else {
                auto namePtr = next;
                auto valuePtr = findCharPtr(next, '=');

                var.name = namePtr[0..valuePtr - namePtr];
                if(*valuePtr == '=') {
                  valuePtr++;
                  next = findCharPtr(valuePtr, '&');
                  var.value = valuePtr[0..next - valuePtr];
                } else {
                  var.value = valuePtr[0..0];
                  next = valuePtr;
                }
                //log("queryVarsRange name=\"%s\" value=\"%s\"", var.name, var.value);
            }
        }
    }
    return Range(varZString);
}

// TODO: make this correct
bool isValidHtmlToken(char c)
{
    return
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      c == '-';
}
inout(char)[] pullContentTypeZString(inout(char)* contentType)
{
    auto start = contentType;
    char c;
    for(;; contentType++) {
        c = *contentType;
        if(!isValidHtmlToken(c)) {
            break;
        }
    }
    if(c == '/') {
        for(;;) {
          contentType++;
          c = *contentType;
          if(!isValidHtmlToken(c)) {
              break;
          }
        }
    }
    return start[0 .. contentType - start];
}

auto contentTypeArgRange(Char)(Char* contentTypeParams)
{
    struct Pair
    {
        Char[] name;
        Char[] value;
    }
    struct Range
    {
        Pair current;
        this(Char* next)
        {
            current.value = next[0..0];
            popFront();
        }
        bool empty() { return current.name is null; }
        auto front() { return current; }
        void popFront()
        {
            auto next = (current.value.ptr + current.value.length).skipCharSet!" ;"();
            if(*next == '\0') {
                current.name = null;
            } else {
                auto nameLimit = next.findCharPtr('=');
                current.name = next[0..nameLimit - next];
                if(*nameLimit == '\0') {
                    current.value = nameLimit[0..0];
                } else {
                    auto valueStart = nameLimit + 1;
                    auto valueEnd = valueStart.findCharPtr(';');
                    current.value = trimRight2(valueStart[0..valueEnd - valueStart]);
                }
            }
        }
    }
    return Range(contentTypeParams);
}
auto httpHeaderArgRange(Char)(Char[] headerArgs)
{
    struct Pair
    {
        Char[] name;
        Char[] value;
    }
    struct Range
    {
        Pair current;
        Char* limit;
        this(Char[] start)
        {
            this.limit = start.ptr + start.length;
            current.value = start.ptr[0..0];
            popFront();
        }
        bool empty() { return current.name is null; }
        auto front() { return current; }
        void popFront()
        {
            auto next = (current.value.ptr + current.value.length).skipCharSet!" ;"(limit);
            if(next == limit) {
                current.name = null;
            } else {
                auto nameLimit = next.findCharPtr(limit, '=');
                current.name = next[0..nameLimit - next];
                if(nameLimit == limit) {
                    current.value = nameLimit[0..0];
                } else {
                    auto valueStart = nameLimit + 1;
                    auto valueEnd = valueStart.findCharPtr(limit, ';');
                    current.value = trimRight2(valueStart[0..valueEnd - valueStart]);
                }
            }
        }
    }
    return Range(headerArgs);
}

inout(char)[] trimNewline(inout(char)[] str)
{
    if(str.length >= 1 && str[$-1] == '\n')
    {
        if(str.length >= 2 && str[$-2] == '\r')
        {
            return str[0..$-2];
        }
        return str[0..$-1];
    }
    return str;
}
inout(char)[] trimRight2(inout(char)[] str)
{
    for(; str.length > 0 && str[$-1] == ' '; str.length--) { }
    return str;
}
void trimRight(const(char)[]* str)
{
    for(;(*str).length > 0 && (*str)[$-1] == ' '; (*str).length--) { }
}

auto asUpper(T)(T c)
{
    return (c >= 'a' && c <= 'z') ? (c - ('a'-'A')) : c;
}
bool strEqualNoCase(const(char)[] left, const(char)[] right)
{
    if(left.length != right.length) {
        return false;
    }
    foreach(i; 0..left.length) {
        if(left[i].asUpper != right[i].asUpper) {
            return false;
        }
    }
    return true;
}

alias noStrings = tuple!();
template strings(T...)
{
    alias strings = T;
}

template HttpTemplate(Hooks)
{
    static assert(Hooks.CookieVars.length == 0 || hasMember!(Env, "HTTP_COOKIE"),
                  "if you configure any CookieVars, you must include HTTP_COOKIE in your EnvVars");
    static assert(Hooks.ReadFormPostData == false || (hasMember!(Env, "CONTENT_TYPE") && hasMember!(Env, "CONTENT_LENGTH")),
                  "if you set ReadFormPostData to true, you must include CONTENT_TYPE and CONTENT_LENGTH in your EnvVars");
    enum ParseUrlVars = (Hooks.UrlVars.length > 0 || Hooks.UrlOrFormVars.length > 0);
    static assert(!ParseUrlVars || hasMember!(Env, "QUERY_STRING"),
                  "if you have any UrlVars or any UrlOrFormVars, you must include QUERY_STRING in your EnvVars");

    struct HttpTemplate
    {
      Env env;
      Cookies cookies;
      UrlVars urlVars;
      FormVars formVars;
      UrlOrFormVars urlOrFormVars;
      string stdinReadBy;

      void init()
      {
        static if(Hooks.ReadFormPostData) {
          bool postContentIsUrlFormData = false;
        }

        // load environment variables
        {
          size_t varsLeft = Hooks.EnvVars.length;
        ENV_LOOP:
          foreach(envPair; envPairs()) {
            foreach(varName; Hooks.EnvVars) {
              if(__traits(getMember, env, varName) is null && envPair.name.strEqualNoCase(varName)) {
                __traits(getMember, env, varName) = envPair.permanentValue;
                static if(varName == "HTTP_COOKIE" && Hooks.CookieVars.length > 0) {
                  parseCookies(__traits(getMember, env, varName));
                } else static if(varName == "CONTENT_TYPE" && Hooks.ReadFormPostData) {
                  if(__traits(getMember, env, varName).startsWith("application/x-www-form-urlencoded")) {
                    postContentIsUrlFormData = true;
                  }
                }
                varsLeft--;
                if(varsLeft == 0) {
                  break ENV_LOOP;
                }
                break;
              }
            }
          }
        }

        static if(Hooks.ReadFormPostData) {
          // read post parameters before url params, url takes precedence
          if(postContentIsUrlFormData) {
            if(env.CONTENT_LENGTH is null) {
              throw new Exception("Content-Type header is set but no Content-Length, this is not implemented");
            }
            // TODO: handle errors when this conversion fails
            auto contentLength = env.CONTENT_LENGTH.to!size_t;
            auto buffer = new char[contentLength + 1];
            {
              auto readLength = stdin.rawRead(buffer[0..contentLength]).length;
              if(readLength != contentLength) {
                throw new Exception(format("based on CONTENT_LENGTH, expected %s bytes of data from stdin but only got %s",
                                          contentLength, readLength));
              }
            }
            stdinReadBy = "the application/x-www-form-urlencoded parser";
            buffer[contentLength] = '\0';
            size_t formVarsLeft = Hooks.FormVars.length;
            size_t urlOrFormVarsLeft = Hooks.UrlOrFormVars.length;
          POST_CONTENT_VAR_LOOP:
            foreach(var; queryVarsRange(buffer.ptr)) {

              foreach(varName; Hooks.FormVars) {
                if(__traits(getMember, formVars, varName) is null && var.name == varName) {
                  __traits(getMember, formVars, varName) = var.value;
                  formVarsLeft--;
                  if(formVarsLeft == 0 && urlOrFormVarsLeft == 0) {
                    break POST_CONTENT_VAR_LOOP;
                  }
                  break;
                }
              }
              foreach(varName; Hooks.UrlOrFormVars) {
                if(__traits(getMember, urlOrFormVars, varName) is null && var.name == varName) {
                  __traits(getMember, urlOrFormVars, varName) = var.value;
                  urlOrFormVarsLeft--;
                  if(formVarsLeft == 0 && urlOrFormVarsLeft == 0) {
                    break POST_CONTENT_VAR_LOOP;
                  }
                  break;
                }
              }
            }
          }
        }

        // read url vars
        static if(ParseUrlVars)
        {
            if(env.QUERY_STRING.ptr)
            {
                uriDecode(env.QUERY_STRING.ptr, env.QUERY_STRING.ptr);

                size_t urlVarsLeft = Hooks.UrlVars.length;
                size_t urlOrFormVarsLeft = Hooks.UrlOrFormVars.length;
            URL_VAR_LOOP:
                foreach(var; queryVarsRange(env.QUERY_STRING.ptr))
                {
                    foreach(varName; Hooks.UrlVars)
                    {
                        if(__traits(getMember, urlVars, varName) is null && var.name == varName)
                        {
                            __traits(getMember, urlVars, varName) = var.value;
                            urlVarsLeft--;
                            if(urlVarsLeft == 0 && urlOrFormVarsLeft == 0)
                            {
                                break URL_VAR_LOOP;
                            }
                            break;
                        }
                    }
                    foreach(varName; Hooks.UrlOrFormVars)
                    {
                        if(__traits(getMember, urlOrFormVars, varName) is null && var.name == varName)
                        {
                            __traits(getMember, urlOrFormVars, varName) = var.value;
                            urlOrFormVarsLeft--;
                            if(urlVarsLeft == 0 && urlOrFormVarsLeft == 0)
                            {
                                break URL_VAR_LOOP;
                            }
                            break;
                        }
                    }
                }
            }
        }
      }
      private void parseCookies(const(char)[] cookieString)
      {
        //log("parseCookies \"%s\"", cookieString);
        size_t varsLeft = Hooks.CookieVars.length;
      COOKIE_LOOP:
        foreach(cookie; cookieRange!(const(char))(cookieString.ptr)) {
          //log("   \"%s\" = \"%s\"", cookie.name, cookie.value);
          foreach(varName; Hooks.CookieVars) {
            if(__traits(getMember, cookies, varName) is null && cookie.name == varName) {
              __traits(getMember, cookies, varName) = cookie.value;
              varsLeft--;
              if(varsLeft == 0) {
                break COOKIE_LOOP;
              }
              break;
            }
          }
        }
      }

      static if(!hasMember!(Env, "CONTENT_TYPE") || !hasMember!(Env, "CONTENT_LENGTH")) {
        bool setupMultipartReader(T)(T* multipart)
        {
          static assert(0, "cannot call setupMultipartReader unless you include CONTENT_TYPE and CONTENT_LENGTH in your EnvVars");
        }
      } else {

        // TODO: checks that the content type is
        bool setupMultipartReader(T)(T* multipart)
        {
          auto contentType = pullContentTypeZString(env.CONTENT_TYPE.ptr);
          if(contentType == "multipart/form-data") {
            if(stdinReadBy) {
              throw new Exception(format("Cannot call setupMultipartReader because stdin was already read by %s", stdinReadBy));
            }
            const(char)[] boundary = null;
            foreach(arg; contentTypeArgRange(env.CONTENT_TYPE.ptr + contentType.length)) {
              if(arg.name == "boundary") {
                boundary = arg.value;
              } else {
                assert(0, format("unknown Content-Type param \"%s\"=\"%s\"", arg.name, arg.value));
              }
            }
            if(boundary is null) {
              assert(0, format("The Content-Type did not contain a boundary parameter \"%s\"", env.CONTENT_TYPE));
            }
            multipart.setBoundaryAndStartReading(boundary);
            stdinReadBy = "multipartReader";
            return true;
          }
          return false;
        }
      }
    }

    struct Env
    {
      mixin(function() {
          auto result = "";
          foreach(varName; Hooks.EnvVars) {
            result ~= "char[] " ~ varName ~ "\n;";
          }
          return result;
        }());
    }
    struct Cookies
    {
      mixin(function() {
          auto result = "";
          foreach(varName; Hooks.CookieVars) {
            result ~= "const(char)[] " ~ varName ~ "\n;";
          }
          return result;
        }());
    }
    struct UrlVars
    {
      mixin(function() {
          auto result = "";
          foreach(varName; Hooks.UrlVars) {
            result ~= "const(char)[] " ~ varName ~ "\n;";
          }
          return result;
        }());
    }
    struct FormVars
    {
      mixin(function() {
          auto result = "";
          foreach(varName; Hooks.FormVars) {
            result ~= "const(char)[] " ~ varName ~ "\n;";
          }
          return result;
        }());
    }
    struct UrlOrFormVars
    {
      mixin(function() {
          auto result = "";
          foreach(varName; Hooks.UrlOrFormVars) {
            result ~= "const(char)[] " ~ varName ~ "\n;";
          }
          return result;
        }());
    }
}


// returns: null on success, ErrnoException on error
ErrnoException tryOpenFile(File* file, const(char)[] filename, in char[] openmode)
{
    try {
        *file = File(filename, openmode);
        return null;
    } catch(ErrnoException e) {
        return e;
    }
}

char[] tryRead(File file)
{
    auto filesize = file.size();
    if(filesize + 1 > size_t.max) {
        assert(0, text(file.name, ": file is too large ", filesize, " > ", size_t.max));
    }
    auto contents = new char[cast(size_t)(filesize + 1)]; // add 1 for '\0'
    auto readSize = file.rawRead(contents).length;
    assert(filesize == readSize, text("rawRead only read ", readSize, " bytes of ", filesize, " byte file"));
    contents[cast(size_t)filesize] = '\0';
    return contents[0..$-1];
}

char[] tryReadFile(const(char)[] filename)
{
    File file;
    try {
        file = File(filename, "rb");
    } catch(ErrnoException e) {
        return null;
    }
    auto filesize = file.size();
    if(filesize + 1 > size_t.max) {
        assert(0, text(filename, ": file is too large ", filesize, " > ", size_t.max));
    }
    auto contents = new char[cast(size_t)(filesize + 1)]; // add 1 for '\0'
    auto readSize = file.rawRead(contents).length;
    assert(filesize == readSize, text("rawRead only read ", readSize, " bytes of ", filesize, " byte file"));
    contents[cast(size_t)filesize] = '\0';
    return contents[0..$-1];
}
// returns error message
string tryWriteFile(T)(const(char)[] filename, const(T)[] content) if(T.sizeof == 1)
{
    File file;
    try {
        file = File(filename, "wb");
    } catch(ErrnoException e) {
        return (e.msg is null) ? "failed to open file" : e.msg; // fail
    }
    scope(exit) file.close();
    file.rawWrite(content);
    return null; // success
}

@property auto defaultGsharedRandom()
{
  static __gshared Random random;
  static __gshared bool seeded = false;

  if(!seeded) {
      random = Random(cast(uint)MonoTime.currTime.ticks);
      seeded = true;
  }
  return &random;
}

void fillRandom(T)(T random, ubyte[] output)
{
    alias UintType = typeof(random.front);

    ubyte shift = UintType.sizeof * 8;
    for(size_t outIndex = 0; outIndex < output.length; outIndex++) {
        if(shift == 0) {
            random.popFront();
            shift = (UintType.sizeof - 1) * 8;
        } else {
            shift -= 8;
        }
        output[outIndex] = cast(ubyte)(random.front >> shift);
    }
}
void fillRandomHex(T)(T random, char[] hex)
    in { assert(hex.length % 2 == 0); } body
{
    // TODO: handle the case where hex is large, then
    //       just generate in chunks
    auto binLength = hex.length / 2;
    auto binPtr = cast(ubyte*)alloca(binLength);
    assert(binPtr !is null);
    auto bin = binPtr[0..binLength];
    fillRandom(random, bin);
    auto formatLength = sformat(hex, "%s", formatHex(bin)).length;
    assert(formatLength == binLength * 2);
}

alias formatJsSingleQuote = formatEscapeSet!(`\`, `\'`);
alias formatJsDoubleQuote = formatEscapeSet!(`\`, `\"`);
alias formatJsonString = formatEscapeSet!(`\`, `\"`);
unittest
{
    assert(`` == format("%s", formatJsonString(``)));
    assert(`a` == format("%s", formatJsonString(`a`)));
    assert(`abcd` == format("%s", formatJsonString(`abcd`)));

    assert(`\"` == format("%s", formatJsonString(`"`)));
    assert(`\\` == format("%s", formatJsonString(`\`)));
    assert(`\"\\` == format("%s", formatJsonString(`"\`)));
    assert(`a\"\\` == format("%s", formatJsonString(`a"\`)));
    assert(`\"a\\` == format("%s", formatJsonString(`"a\`)));
    assert(`\"\\a` == format("%s", formatJsonString(`"\a`)));
    assert(`abcd\"\\` == format("%s", formatJsonString(`abcd"\`)));
    assert(`\"abcd\\` == format("%s", formatJsonString(`"abcd\`)));
    assert(`\"\\abcd` == format("%s", formatJsonString(`"\abcd`)));
}


// returns the amount of characters that were parsed
size_t parseHex(const(char)[] hex, ubyte[] bin)
{
    size_t hexIndex = 0;
    size_t binIndex = 0;
    for(;;) {
        if(hexIndex + 1 > hex.length || binIndex >= bin.length) {
            break;
        }
        auto high = hexValue(hex[hexIndex + 0]);
        auto low  = hexValue(hex[hexIndex + 1]);
        if(high == ubyte.max || low == ubyte.max) {
            break;
        }
        bin[binIndex++] = cast(ubyte)(high << 4 | low);
        hexIndex += 2;
    }
    return hexIndex;
}

bool endsWith(T,U)(T[] str, U[] check)
{
    return str.length >= check.length &&
        str[$ - check.length..$] == check[];
}

struct DefaultStdinReader
{
    // buffer to read data into
    private char[] buffer;
    // length of data meant for the application
    private size_t appDataLength;
    // total length of data in the buffer that has been read
    private size_t readDataLength;
    //@property size_t dataLength() const { return dataLength; }
    @property auto data() { return buffer[0..appDataLength]; }

    void clearData()
    {
        if(appDataLength)
        {
            size_t saveLength = readDataLength - appDataLength;
            if(saveLength)
            {
                /*
                import std.stdio;
                writefln("<pre style=\"color:blue\">shifting (ptr=%s, app=%s,read=%s) %s characters \"%s\"</pre>",
                    cast(void*)&this, appDataLength, readDataLength, saveLength, buffer[appDataLength..readDataLength]);
                    */
                memmove(buffer.ptr, buffer.ptr + appDataLength, saveLength);
            }
            appDataLength = 0;
            readDataLength = saveLength;
        }
    }

    // Note: will only NOT read the given size if EOF is encountered
    void tryRead(size_t size)
        in { assert(size <= buffer.length); } body
    {
        //import std.stdio;
        //writefln("<pre>tryRead(%s) app=%s, read=%s</pre>", size, appDataLength, readDataLength);
        if(size <= readDataLength)
        {
            appDataLength += size;
        }
        else
        {
            auto sizeRead = stdin.rawRead(buffer[readDataLength..size]).length;
            readDataLength += sizeRead;
            appDataLength += sizeRead;
        }
        //writefln("<pre>tryRead returning \"%s\"</pre>", data);
    }
    void readln()
    {
        size_t checked = appDataLength;
        for(;;)
        {
            auto newlineIndex = buffer[checked..readDataLength].indexOf('\n');
            if(newlineIndex >= 0)
            {
                appDataLength = newlineIndex + 1;
                //import std.stdio;
                //writefln("<pre>readln (ptr=%s,app=%s,read=%s) returning \"%s\"</pre>", cast(void*)&this, appDataLength, readDataLength, data);
                return;
            }
            auto bufferLeft = buffer.length - readDataLength;
            if(bufferLeft == 0)
            {
                throw new Exception(format("buffer not large enough, not implemented (data=\"%s\")", asciiFormatEscaped(buffer)));
            }
            auto sizeRead = stdin.rawRead(buffer[readDataLength..$]).length;
            if(sizeRead == 0)
            {
                appDataLength = readDataLength;
                return; // got EOF
            }
            checked = readDataLength;
            readDataLength += sizeRead;
        }
    }
}


struct MultipartFormData
{
    string name;
    string filename;
    string contentType;
    void reset()
    {
        this.name = null;
        this.filename = null;
        this.contentType = null;
    }
}
auto multipartReader(T)(T reader)
{
    return MultipartReader!T(reader);
}
struct MultipartReader(StdinReader)
{
    StdinReader reader;
    private const(char)[] boundary;
    MultipartFormData current;

    @disable this();
    this(StdinReader reader)
    {
        this.reader = reader;
    }
    void setBoundaryAndStartReading(const(char)[] boundary)
    {
        this.boundary = boundary;
        refPopFront();
    }

    auto readln()
    {
        reader.clearData();
        reader.readln();
        return reader.data;
    }

    bool refEmpty() { return current.name is null; }
    MultipartFormData refFront()
    {
        return current;
    }
    void refPopFront()
    {
        //log("MultipartReader.popFront() enter");
        //scope(exit) log("MultipartReader.popFront() exit");


        // read the first 2 bytes
        (&reader).clearData();
        (&reader).tryRead(2);
        if(reader.data != "--")
        {
            throw new Exception(format("Error: expected \"--\" but got \"%s\"", reader.data.asciiFormatEscaped()));
        }
        // todo: handle large boundaries that cannot be read into 1 buffer
        (&reader).clearData();
        (&reader).tryRead(boundary.length);
        // todo: handle EOF here
        if(reader.data != boundary)
        {
            throw new Exception(format("Error: expected boundary \"%s\" but got \"%s\"", boundary, reader.data.asciiFormatEscaped()));
        }

        log("Reading boundary newline...");
        (&reader).clearData();
        (&reader).readln();
        {
            auto rest = reader.data.trimNewline();
            if(rest.length > 0)
            {
                throw new Exception(format("Error: boundary line had %s extra characters \"%s\"", rest.length, rest));
            }
        }

        current.reset();
        bool foundContentDisposition = false;
        for(;;)
        {
            log("Reading line...");
            (&reader).clearData();
            (&reader).readln();
            auto line = reader.data.trimNewline();
            if(line.length == 0)
            {
                log("MultiPartReader.popFront() BLANK", line);
                break;
            }
            log("MultiPartReader.popFront() line \"%s\"", line);
            enum FormDataLinePrefix = "Content-Disposition: form-data";
            if(line.startsWith(FormDataLinePrefix))
            {
                if(foundContentDisposition)
                {
                    throw new Exception("found multiple lines starting with \"%s\"", FormDataLinePrefix);
                }
                foundContentDisposition = true;
                foreach(arg; httpHeaderArgRange(line[FormDataLinePrefix.length..$]))
                {
                    if(arg.name == "name")
                    {
                        if(current.name)
                        {
                            throw new Exception("Content-Disposition 'name' found more than once");
                        }
                        current.name = arg.value.dup;
                    }
                    else if(arg.name == "filename")
                    {
                        if(current.filename)
                        {
                            throw new Exception("Content-Disposition 'filename' found more than once");
                        }
                        current.filename = arg.value.dup;
                    }
                    else
                    {
                        throw new Exception(format("Content-Disposition not implemented, name=\"%s\"", arg.name, arg.value));
                    }
                }
            }
            else
            {
                throw new Exception(format("not implemented, line = \"%s\"", line));
            }
        }
        if(current.name is null)
        {
            throw new Exception("name was not set!");
        }
    }
}

// assumption: str is null terminated
alias zStringByLine = delimited!'\n'.sentinalRange!('\0', const(char));
alias stringByLine = delimited!'\n'.range;
unittest
{
    auto expected = ["a", "bcd", "ef"];
    {
        size_t i = 0;
        foreach(line; zStringByLine("a\nbcd\nef\0")) {
            assert(line == expected[i]);
            i++;
        }
    }
    {
        size_t i = 0;
        foreach(line; stringByLine("a\nbcd\nef")) {
            assert(line == expected[i]);
            i++;
        }
    }
}

//
// Functions to operate on delimited data
//
// delimited data is of the form
// <data> [<delimiter> <data>] *
//
template delimited(char delimiter)
{
    auto sentinalRange(char sentinal = '\0', T)(T* str)
    {
        struct Range
        {
            T[] current;
            T* next;
            this(T* str)
            {
                this.next = str;
                popFront();
            }
            bool empty() { return current.ptr == null; }
            auto front() { return current; }
            void popFront()
            {
                auto start = next;
                if(*start == sentinal) {
                    current = null;
                    return;
                }

                for(;;next++) {
                    auto c = *next;
                    if(c == delimiter) {
                        current = start[0..next-start];
                        next++;
                        return;
                    }
                    if(c == '\0') {
                        current = start[0..next-start];
                        return;
                    }
                }
            }
        }
        return Range(str);
    }
    auto range(T)(T[] str)
    {
        struct Range
        {
            T[] current;
            T[] rest;
            this(T[] str)
            {
                rest = str;
                popFront();
            }
            bool empty() { return current.ptr == null; }
            auto front() { return current; }
            void popFront()
            {
                if(rest.length == 0) {
                    current = null;
                    return;
                }

                for(size_t i = 0;;) {
                    auto c = rest[i];
                    if(c == delimiter) {
                        current = rest[0..i];
                        rest = rest[i + 1..$];
                        return;
                    }
                    i++;
                    if(i >= rest.length) {
                        current = rest;
                        rest = rest[$..$];
                        return;
                    }
                }
            }
        }
        return Range(str);
    }

    enum findFormatCode = q{
    {
        for(;;) {
            auto nextLimit = %s;
            auto value = haystack[0..nextLimit - haystack];
            if(value == needle) {
                return value;
            }
            if(%s) {
                return null;
            }
            haystack = nextLimit + 1;
        }
    }
    };

    mixin(q{
        inout(char)[] find(char sentinal = '\0')(inout(char)* haystack, const(char)[] needle)
    } ~ format(findFormatCode, q{haystack.findCharPtr!sentinal(delimiter)}, q{*nextLimit == sentinal}));
    mixin(q{
      inout(char)[] find(inout(char)* haystack, const(char)* limit,  const(char)[] needle)
    } ~ format(findFormatCode, q{haystack.findCharPtr(limit, delimiter)}, q{nextLimit == limit}));
    pragma(inline)
    inout(char)[] find(inout(char)[] haystack, const(char)[] needle)
    {
        return find(haystack.ptr, haystack.ptr + haystack.length, needle);
    }

    // Appends a string onto an existing string with a delimiter. It checks whether
    // or not the previous string already has a delimiter and won't include the delimiter
    // in that case
    inout(char)[] append(const(char)[] current, inout(char)[] new_)
    {
        if(current.length == 0) {
            return new_;
        }
        if(current[$-1] == delimiter) {
            return cast(inout(char)[])current ~ new_;
        }

        return cast(inout(char)[])current ~ delimiter ~ new_;
    }
    auto removeItem(inout(char)[] current, const(char)[] item)
    {
        return removeItem(current, item.ptr - current.ptr, item.ptr + item.length - current.ptr);
    }
    auto removeItemWithLength(inout(char)[] current, size_t itemStart, size_t itemLength)
    {
        return removeItem(current, itemStart, itemStart + itemLength);
    }
    // doesn't allocate memory if the item is at the beginning or end
    auto removeItem(inout(char)[] current, size_t itemStart, size_t itemLimit) in {
        assert(itemStart <= itemLimit);
        assert(itemLimit <= current.length);
        assert(itemStart == 0 || current[itemStart - 1] == delimiter);
        assert(itemLimit == current.length || current[itemLimit] == delimiter); } body
    {
        if(itemStart == 0) {
            if(itemLimit == current.length) {
                return current[0..0];
            }
            assert(current[itemLimit] == delimiter);
            return current[itemLimit + 1..$];
        }
        assert(current[itemStart - 1] == delimiter);
        if(itemLimit == current.length) {
            return current[0..itemStart - 1];
        }
        return current[0..itemStart - 1] ~ current[itemLimit .. $];
    }
}
unittest
{
    assert("" == delimited!':'.find("\0".ptr, ""));

    assert(null == delimited!':'.find("\0".ptr, "a"));
    assert("a" == delimited!':'.find("a\0".ptr, "a"));
    assert(null == delimited!':'.find("ab\0".ptr, "a"));

    assert(null == delimited!':'.find("\0".ptr, "abcd"));
    assert(null == delimited!':'.find("abc\0".ptr, "abcd"));
    assert("abcd" == delimited!':'.find("abcd\0".ptr, "abcd"));
    assert(null == delimited!':'.find("abcde\0".ptr, "abcd"));

    assert(null == delimited!':'.find("b:c\0".ptr, "a"));
    assert("a" == delimited!':'.find("b:a\0".ptr, "a"));
    assert(null == delimited!':'.find("b:ab\0".ptr, "a"));
    assert("a" == delimited!':'.find("a:b\0".ptr, "a"));
    assert(null == delimited!':'.find("ab:b\0".ptr, "a"));
    assert(null == delimited!':'.find("d:b:e\0".ptr, "a"));
    assert("a" == delimited!':'.find("d:b:e:a\0".ptr, "a"));
    assert(null == delimited!':'.find("d:b:e:ab\0".ptr, "a"));

    assert(null == delimited!':'.find("bbbb:cccc\0".ptr, "aaaa"));
    assert("aaaa" == delimited!':'.find("aaaa:bbbb\0".ptr, "aaaa"));
    assert("aaaa" == delimited!':'.find("bbbb:aaaa\0".ptr, "aaaa"));
    assert(null == delimited!':'.find("bbbb:aaaae\0".ptr, "aaaa"));
    assert(null == delimited!':'.find("dddd:bbbb:eeee\0".ptr, "aaaa"));
    assert("aaaa" == delimited!':'.find("aaaa:bbbb:eeee\0".ptr, "aaaa"));
    assert("aaaa" == delimited!':'.find("bbbb:aaaa:eeee\0".ptr, "aaaa"));
    assert("aaaa" == delimited!':'.find("bbbb:eeee:aaaa\0".ptr, "aaaa"));
    assert("aaaa" == delimited!':'.find("dddd:bbbb:eeee:aaaa\0".ptr, "aaaa"));
    assert(null == delimited!':'.find("ddddd:bbbb:e:aaaaa\0".ptr, "aaaa"));

    // test the other find variations
    assert("a" == delimited!':'.find("a", "a"));
}

unittest
{
    assert("" == delimited!':'.removeItem(null, 0, 0));
    assert("" == delimited!':'.removeItem("", 0, 0));
    assert("" == delimited!':'.removeItem("a", 0, 1));
    assert("b" == delimited!':'.removeItem("a:b", 0, 1));
    assert("a" == delimited!':'.removeItem("a:b", 2, 3));

    assert("b:c" == delimited!':'.removeItem("a:b:c", 0, 1));
    assert("a:c" == delimited!':'.removeItem("a:b:c", 2, 3));
    assert("a:b" == delimited!':'.removeItem("a:b:c", 4, 5));

    assert("efgh:ijkl" == delimited!':'.removeItem("abcd:efgh:ijkl", 0, 4));
    assert("abcd:ijkl" == delimited!':'.removeItem("abcd:efgh:ijkl", 5, 9));
    assert("abcd:efgh" == delimited!':'.removeItem("abcd:efgh:ijkl", 10, 14));
}
