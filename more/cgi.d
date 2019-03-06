module more.cgi;

static import core.stdc.stdio;
import core.stdc.string : strlen, strcpy, memmove;
import core.time : MonoTime, Duration;
import core.stdc.stdlib : alloca;

import std.typecons : Flag, Yes, No;
import std.format : format, sformat;
import std.string : startsWith, indexOf;
import std.algorithm : canFind;
import std.conv : text, to;
import std.traits : hasMember;
import std.typecons : tuple;
import std.random : Random;
import std.exception : ErrnoException;
import std.stdio : File, stdout, stderr, stdin;

import more.parse : hexValue, findCharPtr, skipCharSet;
import more.format : formatEscapeByPolicy, formatEscapeSet, asciiFormatEscaped;
public import more.format : formatHex;
public import more.uri : uriDecode, tryUriDecode;

version = ToLogFile;
version (ToLogFile)
{
    private __gshared bool logFileOpen = false;
    private __gshared File logFile;
}

void log(T...)(T args)
{
    stderr.writeln(args);
    stderr.flush();
}
void logf(T...)(const(char)[] fmt, T args)
{
    version (ToLogFile)
    {
        if (!logFileOpen)
        {
            logFile = File("/tmp/log", "a");
            import std.datetime;
            logFile.writefln("---------------- %s -----------------------", Clock.currTime);
            logFileOpen = true;
        }
        logFile.writefln(fmt, args);
        logFile.flush();
    }
    stderr.writefln(fmt, args);
    stderr.flush();
}

auto fread(T)(ref File file, T[] buffer)
{
    return core.stdc.stdio.fread(buffer.ptr, T.sizeof, buffer.length, file.getFP);
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

bool inHeaders()
{
    return responseState == ResponseState.headers;
}

void assertInHeaders(string functionName)
{
    if(responseState != ResponseState.headers)
    {
        logf("Error: function \"%s\" was called after headers were finished", functionName);
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
        logf("Error: function \"%s\" was called before headers were finished", functionName);
        assert(0, "function \"" ~ functionName ~ "\" was called before headers were finished");
    }
}

@property bool inHeaderState() { return responseState == ResponseState.headers; }
void addHeader(const(char)[] name, const(char)[] value)
{
    assertInHeaders("addHeader");
    stdout.writef("%s: %s\r\n", name, value);
}
void addSetCookieHeader(const(char)[] name, const(char)[] value, Duration expireTimeFromNow = Duration.zero)
{
    assertInHeaders("addSetCookieHeader");
    if(expireTimeFromNow == Duration.zero) {
        stdout.writef("Set-Cookie: %s=%s\r\n", name, value);
    } else {
        assert(0, "not implemented");
    }
}
void addUnsetCookieHeader(const(char)[] name)
{
    assertInHeaders("addUnsetCookieHeader");
    stdout.writef("Set-Cookie: %s=; expires=Thu, 01 Jan 1970 00:00:00 GMT\r\n", name);
}
void finishHeaders()
{
    assertInHeaders("finishHeaders");
    stdout.write("\r\n");
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
    import more.test;
    mixin(scopedTest!"cgi - Hello World");

    // just instantiate the templates
    // all of the following should print "Hello, World!\n"
    if (false)
    {
        write("Hello");
        write(", World!\n");
        write("Hello%s", ", World!\n");
        writeln("Hello, World!");
        writeln("Hello%s", ", World!");
        listWrite("Hello", ", Wo", "rld!\n");
        listWriteln("Hel", "lo, Wo", "rld!");
    }
}

void writeFile(const(char)[] filename)
{
    assertInContent("writeFile");
    auto file = File(filename, "rb");

    enum MAX_BUFFER_SIZE = 8192;
    auto fileSize = file.size();
    auto bufferSize = (fileSize > MAX_BUFFER_SIZE) ? MAX_BUFFER_SIZE : cast(size_t) fileSize;
    auto buffer = new char[bufferSize];
    auto fileLeft = fileSize;
    for(;fileLeft > 0;)
    {
        auto nextReadSize = (fileLeft > bufferSize) ? bufferSize : cast(size_t)fileLeft;
        auto readSize = fread(file, buffer);
        if(readSize == 0)
        {
            auto message = format("only read %s bytes out of %s byte file \"%s\"", fileSize - fileLeft, fileSize, filename);
            logf("Error: %s", message);
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
            //logf("cookieRange.popFront (\"%s\")", next[0..strlen(next)]);
            next = skipCharSet!" ;"(next);
            if(*next == '\0') {
                cookie.name = null;
                //logf("cookieRange.popFront return null");
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
            //logf("cookieRange.popFront name=\"%s\" value=\"%s\"", cookie.name, cookie.value);
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
                //logf("queryVarsRange name=\"%s\" value=\"%s\"", var.name, var.value);
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

/**
Pulls the content-type "token/token" from the "Content-Type: header value.
*/
inout(char)[] pullContentTypeZString(inout(char)* contentType)
{
    if (contentType == null)
        return null;

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

enum HeaderContentType = "Content-Type: ";

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
        Char* next;
        Char* limit;
        this(Char[] start)
        {
            this.next = start.ptr;
            this.limit = start.ptr + start.length;
            popFront();
        }
        bool empty() { return current.name is null; }
        auto front() { return current; }
        void popFront()
        {
            next = next.skipCharSet!" ;"(limit);
            if(next == limit) {
                current.name = null;
            } else {
                auto nameLimit = next.findCharPtr(limit, '=');
                current.name = next[0..nameLimit - next];
                if(nameLimit == limit) {
                    current.value = nameLimit[0..0];
                } else {
                    auto valueStart = nameLimit + 1;
                    next = valueStart.findCharPtr(limit, ';');
                    current.value = trimRight2(valueStart[0..next - valueStart]).escapeQuotesIfThere;
                }
            }
        }
    }
    return Range(headerArgs);
}

inout(char)[] escapeQuotesIfThere(inout(char)[] str)
{
    if (str.length >= 2 && str[0] == '"' && str[$-1] == '"')
    {
        return str[1 ..($-1)]; // TODO: escape the quotes properly
    }
    return str;
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

__gshared string stdinReader = null;

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
              auto readLength = fread(stdin, buffer[0..contentLength]);
              if(readLength != contentLength) {
                throw new Exception(format("based on CONTENT_LENGTH, expected %s bytes of data from stdin but only got %s",
                                          contentLength, readLength));
              }
            }
            stdinReader = "the application/x-www-form-urlencoded parser";
            buffer[contentLength] = '\0';
            size_t formVarsLeft = Hooks.FormVars.length;
            size_t urlOrFormVarsLeft = Hooks.UrlOrFormVars.length;
          POST_CONTENT_VAR_LOOP:
            foreach(var; queryVarsRange(buffer.ptr)) {

              foreach(varName; Hooks.FormVars) {
                
                if(__traits(getMember, formVars, varName) is null && var.name == varName) {
                  __traits(getMember, formVars, varName) = var.value;
                  static if(hasMember!(Hooks, "DisableVarUriDecoding"))
                      bool doDecode = !Hooks.DisableVarUriDecoding;
                  else
                      bool doDecode = true;
                  if (doDecode)
                  {
                      auto result = tryUriDecode(__traits(getMember, formVars, varName));
                      if (result is null)
                      {
                          // TODO: handle this error
                          logf("WARNING: failed to decode post form data variable '%s' (TODO: detect and handle this error)", varName);
                      }
                      else
                      {
                          __traits(getMember, formVars, varName) = result;
                      }
                  }

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
                  static if(hasMember!(Hooks, "DisableVarUriDecoding"))
                      bool doDecode = !Hooks.DisableVarUriDecoding;
                  else
                      bool doDecode = true;
                  if (doDecode)
                  {
                      auto result = tryUriDecode(__traits(getMember, urlOrFormVars, varName));
                      if (result is null)
                      {
                          // TODO: handle this error
                          logf("WARNING: failed to decode post form data variable '%s' (TODO: detect and handle this error)", varName);
                      }
                      else
                      {
                          __traits(getMember, urlOrFormVars, varName) = result;
                      }
                  }
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
        //logf("parseCookies \"%s\"", cookieString);
        size_t varsLeft = Hooks.CookieVars.length;
      COOKIE_LOOP:
        foreach(cookie; cookieRange!(const(char))(cookieString.ptr)) {
          //logf("   \"%s\" = \"%s\"", cookie.name, cookie.value);
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

        static if(hasMember!(Env, "CONTENT_TYPE")/* && !hasMember!(Env, "CONTENT_LENGTH")*/)
        {

            // returns: an error message on error
            string getMultipartBoundary(const(char)[]* outBoundary)
            {
              auto contentType = pullContentTypeZString(env.CONTENT_TYPE.ptr);
              if(contentType != "multipart/form-data")
                return format("Content-Type is not 'multipart/form-data', it is '%s'", contentType);

              foreach(arg; contentTypeArgRange(env.CONTENT_TYPE.ptr + contentType.length)) {
                if(arg.name == "boundary") {
                  *outBoundary = arg.value;
                  return null; // no error
                } else {
                  // ignore
                  //assert(0, format("unknown Content-Type param \"%s\"=\"%s\"", arg.name, arg.value));
                }
              }
              return format("Content-Type '%s' is missing the 'boundary' parameter", env.CONTENT_TYPE);
            }

            /**
            Returns: null on success, error message on error
            */
            string uploadFile(const(char)[] fileFormName, char[] uploadBuffer,
                string delegate(const(char)[] clientFilename, string* serverFilename) onFilename)
            {
                // TODO: might need to support variables as well
                const(char)[] boundary;
                {
                    auto error = getMultipartBoundary(&boundary);
                    if (error !is null)
                        return error;
                }
                auto reader = StdinMultipartReader(uploadBuffer, boundary);

                for (auto partResult = reader.start(); ;partResult = reader.readHeaders())
                {
                    if (partResult.isDone)
                        return "missing file from post data";
                    if (partResult.isError)
                        return partResult.makeErrorMessage();

                    if (partResult.formData.name != "file")
                        return format("got unknown form variable '%s'", partResult.formData.name);

                    if (partResult.formData.filename.canFind('/'))
                        return format("filename '%s' contains slashes", partResult.formData.filename);

                    string serverFilename = null;
                    {
                        auto error = onFilename(partResult.formData.filename, &serverFilename);
                        if (error !is null)
                            return error;
                    }
                    if (serverFilename is null)
                        serverFilename = partResult.formData.filename;

                    auto file = File(serverFilename, "wb");
                    for (;;)
                    {
                        auto contentResult = reader.readContent();
                        if (contentResult.isError)
                            return contentResult.makeErrorMessage();

                        //writeln("<pre>got %s bytes of content data</pre>", contentResult.content.length);
                        file.rawWrite(contentResult.content);
                        if (contentResult.gotBoundary)
                            break;
                    }
                    return null; // success
                }
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
    auto readSize = fread(file, contents);
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
    auto readSize = fread(file, contents);
    assert(filesize == readSize, text("fread only read ", readSize, " bytes of ", filesize, " byte file"));
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
    import more.test;
    mixin(scopedTest!"cgi - formatJsonString");

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

/**
Returns:`buffer.length` on success, negative on error, otherwise, the number of bytes read before EOF
*/
//
auto readFull(Policy)(char[] buffer)
{
    size_t totalRead = 0;
    for (;;)
    {
        if (totalRead == buffer.length)
            return totalRead;
        auto result = Policy.read(buffer[totalRead .. $]);
        if (result <= 0)
        {
            if (result == 0)
                return totalRead;
            return result;
        }

        totalRead += result;
    }
}

auto upTo(T)(T array, char toChar)
{
    auto charIndex = array.indexOf(toChar);
    return (charIndex < 0) ? array : array[0 .. charIndex];
}

auto indexOfParts(U, T...)(U haystack, T parts)
{
    ptrdiff_t offset = 0;
    for (;;)
    {
        auto next = haystack[offset .. $].indexOf(parts[0]);
        if (next == -1)
            return -1;
        offset += next;
        next = offset + parts[0].length;
        bool mismatch = false;
        foreach (part; parts[1 .. $])
        {
            if (!haystack[next .. $].startsWith(part))
            {
                mismatch = true;
                break;
            }
            next += part.length;
        }
        if (!mismatch)
            return offset;
        offset++;
    }
}
unittest
{
    assert("1234".indexOfParts("2") == 1);
    assert("1234".indexOfParts("2", "3") == 1);
    assert("1234".indexOfParts("23") == 1);
    assert("1234".indexOfParts("23", "4") == 1);
    assert("1234".indexOfParts("2", "34") == 1);
    assert("123456789".indexOfParts("567", "8") == 4);
    assert("123456789".indexOfParts("5", "678") == 4);
    assert("123456789".indexOfParts("5", "67", "89") == 4);
    assert("1231234123".indexOfParts("1", "2", "34") == 3);
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

struct MultipartReaderTemplate(Policy)
{
    // TODO: mabye create a mixin for this
    static struct ReadHeadersResult
    {
        static ReadHeadersResult atContent(MultipartFormData formData) { return ReadHeadersResult(formData); }
        static ReadHeadersResult done() { return ReadHeadersResult(State.done); }
        static ReadHeadersResult policyError(string errorMsg)
        {
            auto r = ReadHeadersResult(State.policyError);
            r.str = errorMsg;
            return r;
        }
        static ReadHeadersResult bufferTooSmallForBoundary() { return ReadHeadersResult(State.bufferTooSmallForBoundary); }
        static ReadHeadersResult bufferTooSmallForHeaders() { return ReadHeadersResult(State.bufferTooSmallForHeaders); }
        static ReadHeadersResult readError(int errorNumber)
        {
            auto r = ReadHeadersResult(State.readError);
            r.int_ = errorNumber;
            return r;
        }
        static ReadHeadersResult invalidFirstBoundary() { return ReadHeadersResult(State.invalidFirstBoundary); }
        static ReadHeadersResult invalidBoundaryPostfix() { return ReadHeadersResult(State.invalidBoundaryPostfix); }
        static ReadHeadersResult headerTooBig() { return ReadHeadersResult(State.headerTooBig); }
        static ReadHeadersResult eofInsideHeaders() { return ReadHeadersResult(State.eofInsideHeaders); }
        static ReadHeadersResult unknownHeader(char[] s)
        {
            auto r = ReadHeadersResult(State.unknownHeader);
            r.charArray = s;
            return r;
        }
        static ReadHeadersResult missingContentDisposition() { return ReadHeadersResult(State.missingContentDisposition); }
        static ReadHeadersResult unknownContentDispositionArg(char[] s)
        {
            auto r = ReadHeadersResult(State.unknownContentDispositionArg);
            r.charArray = s;
            return r;
        }
        static ReadHeadersResult contentDispositionMissingFormData() { return ReadHeadersResult(State.contentDispositionMissingFormData); }
        static ReadHeadersResult contentDispositionMissingName() { return ReadHeadersResult(State.contentDispositionMissingName); }

        private enum State : ubyte
        {
            atContent,
            done,
            // error states
            errorStates,
            policyError = errorStates,
            bufferTooSmallForBoundary,
            bufferTooSmallForHeaders,
            readError,
            invalidFirstBoundary,
            invalidBoundaryPostfix,
            headerTooBig,
            eofInsideHeaders,
            unknownHeader,
            missingContentDisposition,
            unknownContentDispositionArg,
            contentDispositionMissingFormData,
            contentDispositionMissingName,
        }
        State state;
        union
        {
            MultipartFormData formData;
            char[] charArray;
            string str;
            int int_;
        }
        private this(State state)
        {
            this.state = state;
        }
        private this(MultipartFormData formData)
        {
            this.state = State.atContent;
            this.formData = formData;
        }

        bool isError() const { return state >= State.errorStates; }
        bool isDone() const { return state == State.done; }

        string makeErrorMessage() const
        {
            final switch(state)
            {
                case State.atContent: return "no error";
                case State.done: return "no error";
                case State.policyError: return str;
                case State.bufferTooSmallForBoundary:
                    return "upload buffer too small (cannot hold boundary)";
                case State.bufferTooSmallForHeaders:
                    return "upload buffer too small (cannot hold headers)";
                case State.readError:
                    return format("read failed (e=%d)", int_);
                case State.invalidFirstBoundary:
                    return "invalid upload data (initial boundary is not right)";
                case State.invalidBoundaryPostfix:
                    return "invalid upload data (invalid boundary postfix)";
                case State.headerTooBig:
                    return format("invalid upload data (header exceeded max size of %s)", Policy.MaxHeader);
                case State.eofInsideHeaders:
                    return "invalid upload data (input ended inside headers)";
                case State.unknownHeader:
                    return format("invalid upload data (unrecognized header '%s')", charArray);
                case State.missingContentDisposition:
                    return "invalid upload data (missing Content-Disposition)";
                case State.unknownContentDispositionArg:
                    return format("invalid upload data (unknown Content-Disposition arg '%s')", charArray);
                case State.contentDispositionMissingFormData:
                    return "invalid upload data (Content-Disposition is missing form-data argument)";
                case State.contentDispositionMissingName:
                    return "invalid upload data (Content-Disposition is missing name argument)";
            }
        }
    }

    char[] buffer;
    const(char)[] boundary;
    size_t dataOffset;
    size_t dataLimit;

    pragma(inline) auto encapsulateBoundaryLength() const
    {
        return 4 +                // "\r\n--"
               boundary.length ;  // Content-Type boundary string
    }
    ReadHeadersResult start()
    {
        {
            auto error = Policy.checkForErrorBeforeStart();
            if (error !is null)
                return ReadHeadersResult.policyError(error);
        }
        // TODO: the multipart content could start with a prologue instead
        //       of starting with the boundary right away
        auto firstBoundaryLength = 2 + boundary.length; // "--" ~ boundary
        if (buffer.length < firstBoundaryLength)
            return ReadHeadersResult.bufferTooSmallForBoundary;

        auto result = readFull!Policy(buffer[0 .. firstBoundaryLength]);
        if (result != firstBoundaryLength)
        {
            if (result == 0)
                return ReadHeadersResult.done;
            return ReadHeadersResult.readError(Policy.getError(result));
        }
        if (buffer[0 .. 2] != "--" ||
            buffer[2 .. 2 + boundary.length] != boundary)
            return ReadHeadersResult.invalidFirstBoundary;
        dataOffset = 0;
        dataLimit = 0;
        return readHeaders();
    }

    /** shift current data to the beginning of the buffer */
    private void shiftData()
    {
        auto saveLength = dataLimit - dataOffset;
        if (saveLength > 0)
        {
            memmove(buffer.ptr, buffer.ptr + dataOffset, saveLength);
        }
        dataOffset = 0;
        dataLimit = saveLength;
    }

    // returns: positive on success, 0 on EOF, negative on error
    private auto ensureSmallDataSizeAvailable(uint size)
    in { /*assert(size <= buffer.length);*/ } do
    {
        auto dataSize = dataLimit - dataOffset;
        if (size > dataSize)
        {
            shiftData();
            auto bufferAvailable = buffer.length - dataLimit;
            auto sizeToRead = size - dataSize;
            // NOTE: sizeToRead must be <= (buffer.length - dataLimit)
            //       because size <= buffer.length
            auto result = Policy.read(buffer[dataLimit .. dataLimit + sizeToRead]);
            if (result <= 0)
                return result;
            dataLimit += result;
            if (result != sizeToRead)
                return -1;
            return result;
        }
        return 1; // success
    }

    ReadHeadersResult readHeaders()
    {
        // check whether we start with a "\r\n" or "--"
        {
            auto result = ensureSmallDataSizeAvailable(2);
            if (result <= 0)
            {
                if (result == 0)
                    return ReadHeadersResult.eofInsideHeaders;
                return ReadHeadersResult.readError(Policy.getError(result));
            }
        }
        auto boundaryPostfix = buffer[dataOffset .. dataOffset + 2];
        if (boundaryPostfix == "\r\n")
            dataOffset += 2;
        else if (boundaryPostfix == "--")
            return ReadHeadersResult.done;
        else
            return ReadHeadersResult.invalidBoundaryPostfix;

        MultipartFormData formData;
        auto checkIndex = dataOffset;
        //import std.stdio; writefln("+ readHeaders (checkIndex=%s, dataSize=%s)", checkIndex, dataLimit - dataOffset);
        for (;;)
        {
            // find the end of the next header
            auto newlinePos = buffer[checkIndex .. dataLimit].indexOf("\n");
            //import std.stdio; writefln("newlinePos=%s, (checkIndex=%s)", newlinePos, checkIndex);
            if (newlinePos == -1)
            {
                shiftData();
                if (dataLimit > Policy.MaxHeader)
                    return ReadHeadersResult.headerTooBig();
                auto bufferAvailable = buffer.length - dataLimit;
                if (bufferAvailable == 0)
                    return ReadHeadersResult.bufferTooSmallForHeaders;
                // TODO: don't read TOO much, we don't want to
                //       end up "shifting" too much data
                auto result = Policy.read(buffer[dataLimit .. $]);
                //import std.stdio; writefln("read %s bytes", result);
                if (result <= 0)
                {
                    if (result == 0)
                    {
                        if (dataOffset == dataLimit) {
                            return ReadHeadersResult.done;
                        }
                        return ReadHeadersResult.eofInsideHeaders;
                    }
                    return ReadHeadersResult.readError(Policy.getError(result));
                }
                checkIndex = dataLimit;
                dataLimit += result;
            }
            else
            {
                auto newlineOffset = checkIndex + newlinePos;
                auto header = buffer[dataOffset .. newlineOffset - 1];
                dataOffset = newlineOffset + 1;
                //import std.stdio; writefln("header = '%s'", header.asciiFormatEscaped);

                if (header.length == 0)
                {
                    if (formData.name is null)
                        return ReadHeadersResult.missingContentDisposition;
                    return ReadHeadersResult.atContent(formData);
                }
                import std.algorithm : skipOver;
                if (header.skipOver("Content-Disposition: "))
                {
                    if (!header.skipOver("form-data"))
                        return ReadHeadersResult.contentDispositionMissingFormData;
                    foreach(arg; httpHeaderArgRange(header))
                    {
                        if(arg.name == "name")
                            formData.name = Policy.allocName(arg.value);
                        else if(arg.name == "filename")
                            formData.filename = Policy.allocName(arg.value);
                        else
                            return ReadHeadersResult.unknownContentDispositionArg(arg.name);
                    }
                    if (formData.name is null)
                        return ReadHeadersResult.contentDispositionMissingName;
                    //import std.stdio; writefln("formData.name = '%s'", formData.name);
                }
                else if (header.skipOver("Content-Type: "))
                {
                    formData.contentType = Policy.allocName(header);
                }
                else
                {
                    return ReadHeadersResult.unknownHeader(header.upTo(':'));
                }
                checkIndex = dataOffset;
            }
        }
    }

    static struct ReadContentResult
    {
        static ReadContentResult contentButNoBoundaryYet(char[] content)
        {
            ReadContentResult result = void;
            result.state = State.contentButNoBoundaryYet;
            result._content = content;
            return result;
        }
        static ReadContentResult contentWithBoundary(char[] content)
        {
            ReadContentResult result = void;
            result.state = State.contentWithBoundary;
            result._content = content;
            return result;
        }
        static ReadContentResult bufferTooSmallForBoundary()
        { return ReadContentResult(State.bufferTooSmallForBoundary); }
        static ReadContentResult noEndingBoundary()
        { return ReadContentResult(State.noEndingBoundary); }
        static ReadContentResult readError(int errorNumber)
        {
            auto r = ReadContentResult(State.readError);
            r.int_ = errorNumber;
            return r;
        }

        private enum State : ubyte
        {
            // gotContent states
            contentButNoBoundaryYet,
            contentWithBoundary,
            // error states
            errorStates,
            bufferTooSmallForBoundary = errorStates,
            noEndingBoundary,
            readError,
        }
        State state;
        union
        {
            private char[] _content;
            private int int_;
        }
        bool isError() const { return state >= State.errorStates; }
        char[] content() const { return cast(char[])_content; }
        bool gotBoundary() const { return state == State.contentWithBoundary; }

        string makeErrorMessage() const
        {
            final switch(state)
            {
                case State.contentButNoBoundaryYet: return "no error";
                case State.contentWithBoundary: return "no error";
                case State.bufferTooSmallForBoundary:
                    return "upload buffer too small (cannot hold boundary)";
                case State.noEndingBoundary:
                    return "invalid upload data (missing terminating boundary)";
                case State.readError:
                    return format("read failed (e=%d)", int_);
            }
        }
    }
    ReadContentResult readContent()
    {
        auto checkIndex = dataOffset;
        //import std.stdio; writefln("+ readContent (checkIndex=%s, dataSize=%s)", checkIndex, dataLimit - dataOffset);
        for (;;)
        {
            //import std.stdio; writefln("readContent Loop");
            auto nextBoundaryPos = buffer[checkIndex .. dataLimit].indexOfParts("\r\n--", boundary);
            if (nextBoundaryPos == -1)
            {
                //import std.stdio; writefln("boundary not found!");
                auto dataLength = dataLimit - dataOffset;
                if (dataLength >= encapsulateBoundaryLength) {
                    auto returnLimit = dataLimit - (encapsulateBoundaryLength - 1);
                    auto content = buffer[dataOffset .. returnLimit];
                    //import std.stdio; writefln("returning data %s to %s", dataOffset, returnLimit);
                    dataOffset = returnLimit;
                    return ReadContentResult.contentButNoBoundaryYet(content);
                }
                // we need to read more data
                shiftData();
                auto bufferAvailable = buffer.length - dataLimit;
                //import std.stdio; writefln("readContent shift (data=%s, available=%s)", dataLimit, bufferAvailable);
                if (bufferAvailable == 0)
                    return ReadContentResult.bufferTooSmallForBoundary;
                // TODO: don't read TOO much, we don't want to
                //       end up "shifting" too much data
                auto result = Policy.read(buffer[dataLimit .. $]);
                //import std.stdio; writefln("read %s bytes (in readContent)", result);
                if (result <= 0)
                {
                    if (result == 0)
                        return ReadContentResult.noEndingBoundary;
                    return ReadContentResult.readError(Policy.getError(result));
                }
                if (dataLimit > (encapsulateBoundaryLength - 1))
                    checkIndex = dataLimit - (encapsulateBoundaryLength - 1);
                else
                    checkIndex = 0;
                dataLimit += result;
//                import std.stdio; writefln("checkIndex = %s, dataLimit=%s, encapsulateBoundaryLength=%s check='%s'",
//                    checkIndex, dataLimit, encapsulateBoundaryLength, buffer[checkIndex .. dataLimit]);
//                import std.stdio; writefln("checkIndex = %s, dataLimit=%s, encapsulateBoundaryLength=%s",
//                    checkIndex, dataLimit, encapsulateBoundaryLength);
            }
            else
            {
                //import std.stdio; writefln("foundBoundary!");
                auto nextBoundaryIndex = checkIndex + nextBoundaryPos;
                auto contentStart = dataOffset;
                dataOffset = nextBoundaryIndex + encapsulateBoundaryLength;
                return ReadContentResult.contentWithBoundary(buffer[contentStart .. nextBoundaryIndex]);
            }
        }
    }
}

version (linux)
{
    extern(C) ptrdiff_t read(int fd, void* ptr, size_t len);
}
else static assert(0, "read function not implemented on this platform");

private struct StdinMultipartReaderPolicy
{
    enum MaxHeader = 200;
    // returns error message if we cannot start reading
    static string checkForErrorBeforeStart()
    {
        if (stdinReader)
            return format("CodeBug: cannot use StdinMultipartReader because stdin was already read by '%s'", stdinReader);
        stdinReader = "multipartReader";
        return null; // no errors
    }
    static auto read(char[] buffer)
    {
        return .read(0, buffer.ptr, buffer.length);
    }
    static auto getError(ptrdiff_t result)
    {
        static import core.stdc.errno;
        return core.stdc.errno.errno;
    }
    static auto allocName(const(char)[] name)
    {
        return name.idup;
    }
}
alias StdinMultipartReader = MultipartReaderTemplate!StdinMultipartReaderPolicy;

unittest
{
    static char[] inBuffer;
    static size_t inOffset;
    static size_t inLimit;
    inBuffer = new char[3000];
    static void setInData(string s)
    {
        //import std.stdio; writefln("inData '%s'", s);
        inBuffer[0 .. s.length] = s;
        inOffset = 0;
        inLimit = s.length;
    }
    static string generateTestContent(size_t size)
    {
        static hexmap = "0123456789abcdef";
        auto content = new char[size];
        foreach (i; 0 .. size) {
            content[i] = hexmap[i & 0b1111];
        }
        return cast(string)content;
    }
    static struct TestMultipartReaderPolicy
    {
        enum MaxHeader = 200;
        pragma(inline)
        static string checkForErrorBeforeStart()
        {
            return null; // no error
        }
        pragma(inline)
        static auto read(char[] buffer)
        {
            //import std.stdio; writefln("ReadCall (in %s-%s) (size=%s)", inOffset, inLimit, buffer.length);
            auto readSize = inLimit - inOffset;
            if (buffer.length < readSize)
                readSize = buffer.length;
            buffer[0 .. readSize] = inBuffer[inOffset .. inOffset + readSize];
            inOffset += readSize;
            return readSize;
        }
        static auto getError(ptrdiff_t result)
        {
            assert(0, "not implemented");
            return result;
        }
        static auto allocName(const(char)[] name)
        {
            return name.idup;
        }
    }
    alias TestMultipartReader = MultipartReaderTemplate!TestMultipartReaderPolicy;
    char[  1]   buffer1;
    char[  4]   buffer4;
    char[100] buffer100;
    {
        setInData("");
        auto reader = TestMultipartReader(buffer100, "MYBOUNDARY");
        assert(reader.start().isDone);
    }
    {
        setInData("--MYBOUNDARY\r\n\r\n");
        auto reader = TestMultipartReader(buffer100, "MYBOUNDARY");
        assert(reader.start().state == TestMultipartReader.ReadHeadersResult.State.missingContentDisposition);
    }
    {
        setInData("--MYBOUNDARY\r\n"
            ~ "Content-Disposition: form-data; name=\"TestVariable\"\r\n\r\n");
        auto reader = TestMultipartReader(buffer100, "MYBOUNDARY");
        auto result = reader.start();
        assert(!result.isError);
    }
    {
        setInData("--MYBOUNDARY\r\n"
            ~ "Content-Disposition: form-data; name=\"TestVar\"\r\n"
            ~ "Content-Type: plain/text\r\n\r\n");
        auto reader = TestMultipartReader(buffer100, "MYBOUNDARY");
        auto result = reader.start();
        assert(!result.isError);

    }
    {
        setInData("--MYBOUNDARY\r\n"
            ~ "Content-Disposition: form-data; name=\"TestVar\"\r\n"
            ~ "Content-Type: plain/text\r\n\r\n"
            ~ "\r\n--MYBOUNDARY\r\n");
        auto reader = TestMultipartReader(buffer100, "MYBOUNDARY");
        {
            auto result = reader.start();
            assert(!result.isError);
        }
        {
            auto result = reader.readContent();
            assert(result.gotBoundary);
            assert(result.content.length == 0);
        }
        {
            auto result = reader.readHeaders();
            assert(result.isDone);
        }
    }

    static void readAndDropContent(TestMultipartReader* reader)
    {
        for (;;)
        {
            auto result = reader.readContent();
            assert(!result.isError);
            if (result.gotBoundary)
                return;
        }
    }
    static void readAndDropContentSize(TestMultipartReader* reader, size_t contentLeft)
    {
        for (;;)
        {
            auto result = reader.readContent();
            assert(!result.isError);
            if (result.content.length > contentLeft)
            {
                import std.stdio;
                writefln("result.content.length %s contentLeft %s", result.content.length, contentLeft);
            }
            assert(result.content.length <= contentLeft);
            contentLeft -= result.content.length;
            if (contentLeft == 0)
            {
                if (result.gotBoundary)
                    return;
            }
            assert(!result.gotBoundary);
        }
    }

    foreach (bufferSize; 50 .. 101)
    {
        foreach (contentSize; 0 .. 301)
        {
            setInData("--MYBOUNDARY\r\n"
                ~ "Content-Disposition: form-data; name=\"TestVar\"\r\n"
                ~ "Content-Type: plain/text\r\n\r\n"
                ~ generateTestContent(contentSize)
                ~ "\r\n--MYBOUNDARY\r\n");
            auto reader = TestMultipartReader(buffer100[0 .. bufferSize], "MYBOUNDARY");
            {
                auto result = reader.start();
                assert(!result.isError);
            }
            readAndDropContentSize(&reader, contentSize);
            {
                auto result = reader.readHeaders();
                //import std.stdio; writefln("state = %s", result.state);
                assert(result.isDone);
            }
        }
    }

    foreach (bufferSize; 60 .. 101)
    {
        setInData(  "------WebKitFormBoundaryDL9nQxvP3BPx3UvL\r\n"
                  ~ "Content-Disposition: form-data; name=\"TestVariable1\"\r\n"
                  ~ "\r\n"
                  ~ "TestValue1\r\n"
                  ~ "------WebKitFormBoundaryDL9nQxvP3BPx3UvL\r\n"
                  ~ "Content-Disposition: form-data; name=\"TestVariable2\"\r\n"
                  ~ "\r\n"
                  ~ "TestValue2\r\n"
                  ~ "------WebKitFormBoundaryDL9nQxvP3BPx3UvL\r\n"
                  ~ "Content-Disposition: form-data; name=\"TestVariable3\"\r\n"
                  ~ "\r\n"
                  ~ "TestValue3\r\n"
                  ~ "------WebKitFormBoundaryDL9nQxvP3BPx3UvL\r\n"
                  ~ "Content-Disposition: form-data; name=\"file\"; filename=\"10bytesandnewline.txt\"\r\n"
                  ~ "Content-Type: text/plain\r\n"
                  ~ "\r\n"
                  ~ "0123456789\r\n"
                  ~ "\r\n"
                  ~ "------WebKitFormBoundaryDL9nQxvP3BPx3UvL--\r\n");
        auto reader = TestMultipartReader(buffer100[0 .. bufferSize], "----WebKitFormBoundaryDL9nQxvP3BPx3UvL");
        {
            auto result = reader.start();
            assert(!result.isError);
        }
        readAndDropContentSize(&reader, 10);
    }

}


// Assumption: str is null terminated
alias zStringByLine = delimited!'\n'.sentinalRange!('\0', const(char));
alias stringByLine = delimited!'\n'.range;
unittest
{
    import more.test;
    mixin(scopedTest!"cgi - strings by line");

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
        if (haystack == null)
            return null;
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
    import more.test;
    mixin(scopedTest!"cgi - delimited 1");

    assert("" == delimited!':'.find(cast(char*)null, ""));
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
    import more.test;
    mixin(scopedTest!"cgi - delimited 2");

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
