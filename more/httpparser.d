module more.httpparser;

import std.typecons : BitFlags, Flag, Yes, No;

enum HttpBadRequestReason
{
    invalidMethodCharacter,
    methodNameTooLong,
    badHttpVersion,
    invalidHeaderNameCharacter,
    headerNameTooLong,
}

template HttpParser(H)
{
    enum SaveHeaderValueState : ubyte
    {
        noNewline,
        carriageReturn, // '\r'
        lineFeed,       // '\n
    }
    static if(H.SupportCallbackStop)
    {
        alias OnReturnType = Flag!"stop";
        string genCallbackCode(string call)
        {
            return `if(` ~ call ~ `) { parser.nextParse = &parseDone; return; }`;
        }
    }
    else
    {
        alias OnReturnType = void;
        string genCallbackCode(string call)
        {
            return call ~ ";";
        }
    }

    struct HttpParser
    {
        private void function(HttpParser* parser, H.DataType[] buffer) nextParse = &parseMethod;
        union
        {
            uint parserStateUint0;
            static if(H.SupportPartialData)
            {
                SaveHeaderValueState headerValueState;
            }
        }
        mixin H.HttpParserMixinTemplate;
        void reset()
        {
            this = this.init;
        }
        @property bool done() const
        {
            return nextParse is &parseDone;
        }
        void parse(H.DataType[] buffer)
        {
            nextParse(&this, buffer);
        }
    }
    private final void parseInvalidState(HttpParser* parser, H.DataType[] buffer)
    {
        assert(0, "parse was called in an invalid state!");
    }
    private final void parseDone(HttpParser* parser, H.DataType[] buffer)
    {
        assert(0, "the http parser is done");
    }
    private final void parseMethod(HttpParser* parser, H.DataType[] buffer)
    {
        for(uint i = 0; i < buffer.length; i++)
        {
            if(' ' == buffer[i] )
            {
                mixin(genCallbackCode(`H.onMethod(parser, buffer[0..i])`));
                parser.nextParse = &parseUri;
                parseUri(parser, buffer[i + 1..$]);
                return;
            }
            if(!validTokenChar(buffer[i]))
            {
                H.onBadRequest(parser, HttpBadRequestReason.invalidMethodCharacter);
                parser.nextParse = &parseInvalidState;
                return;
            }
            if(i >= H.MaximumMethodName)
            {
                H.onBadRequest(parser, HttpBadRequestReason.methodNameTooLong);
                parser.nextParse = &parseInvalidState;
                return;
            }
        }

        static if(H.SupportPartialData)
        {
            mixin(genCallbackCode(`H.onMethodPartial(parser, buffer)`));
        }
        else
        {
            assert(0, "partial data unsupported");
        }
    }


    /*
    grammar here: https://tools.ietf.org/html/rfc3986#section-3
        URI       = [ scheme ":" hier-part ] [ "?" query ] [ "#" fragment ]
        hier-part = "//" authority path-abempty
                  / path-absolute
                  / path-rootless
                  / path-empty
    */
    private final void parseUri(HttpParser* parser, H.DataType[] buffer)
    {
        for(uint i = 0; i < buffer.length; i++)
        {
            if(' ' == buffer[i])
            {
                mixin(genCallbackCode(`H.onUri(parser, buffer[0..i])`));
                parser.nextParse = &parseVersionAndNewline;
                parser.parserStateUint0 = 0;
                parseVersionAndNewline(parser, buffer[i + 1..$]);
                return;
            }
            /*
            TODO: check if there is a maximum URI and/or if the URI is valid
            if(!validTokenChar(buffer[i]))
            {
                H.onBadRequest(parser, HttpBadRequestReason.invalidMethodCharacter);
                parser.nextParse = &parseInvalidState;
                return;
            }
            if(i >= H.MaximumMethodName)
            {
                H.onBadRequest(parser, HttpBadRequestReason.methodNameTooLong);
                parser.nextParse = &parseInvalidState;
                return;
            }
            */
        }

        static if(H.SupportPartialData)
        {
            mixin(genCallbackCode(`H.onUriPartial(parser, buffer)`));
        }
        else
        {
            assert(0, "partial data unsupported");
        }
    }

    enum HTTP_VERSION_AND_NEWLINE = "HTTP/1.1\r\n";
    private final void parseVersionAndNewline(HttpParser* parser, H.DataType[] buffer)
    {
        uint compareLength = cast(uint)HTTP_VERSION_AND_NEWLINE.length - parser.parserStateUint0;
        if(compareLength > buffer.length)
        {
            if(HTTP_VERSION_AND_NEWLINE[parser.parserStateUint0..parser.parserStateUint0 + buffer.length] != buffer[])
            {
                H.onBadRequest(parser, HttpBadRequestReason.badHttpVersion);
                parser.nextParse = &parseInvalidState;
                return;
            }
            parser.parserStateUint0 += buffer.length;
        }
        else
        {
            if(HTTP_VERSION_AND_NEWLINE[parser.parserStateUint0..$] != buffer[0..compareLength])
            {
                H.onBadRequest(parser, HttpBadRequestReason.badHttpVersion);
                parser.nextParse = &parseInvalidState;
                return;
            }
            parser.nextParse = &initialParseHeaderName;
            initialParseHeaderName(parser, buffer[compareLength..$]);
        }
    }

    private final void parseNewline(HttpParser* parser, H.DataType[] buffer)
    {
        if(buffer.length > 0)
        {
            if(buffer[0] == '\n')
            {
                H.onHeadersDone(parser, buffer[1..$]);
                parser.nextParse = &parseDone;
            }
        }
    }

    private final void initialParseHeaderName(HttpParser* parser, H.DataType[] buffer)
    {
        if(buffer.length > 0)
        {
            // Check for "\r\n" to end headers
            if(buffer[0] == '\r')
            {
                parser.nextParse = &parseNewline;
                parseNewline(parser, buffer[1..$]);
            }
            else
            {
                parser.nextParse = &parseHeaderName;
                parseHeaderName(parser, buffer);
            }
        }
    }
    private final void parseHeaderName(HttpParser* parser, H.DataType[] buffer)
    {
        for(uint i = 0; i < buffer.length; i++)
        {
            if(':' == buffer[i] )
            {
                mixin(genCallbackCode(`H.onHeaderName(parser, buffer[0..i])`));
                parser.nextParse = &initialParseHeaderValue;
                initialParseHeaderValue(parser, buffer[i + 1..$]);
                return;
            }
            if(!validTokenChar(buffer[i]))
            {
                H.onBadRequest(parser, HttpBadRequestReason.invalidHeaderNameCharacter);
                parser.nextParse = &parseInvalidState;
                return;
            }
            if(i >= H.MaximumHeaderName)
            {
                H.onBadRequest(parser, HttpBadRequestReason.headerNameTooLong);
                parser.nextParse = &parseInvalidState;
                return;
            }
        }
        static if(H.SupportPartialData)
        {
            mixin(genCallbackCode(`H.onHeaderNamePartial(parser, buffer)`));
        }
        else
        {
            assert(0, "partial data unsupported");
        }
    }
    private final void initialParseHeaderValue(HttpParser* parser, H.DataType[] buffer)
    {
        // skip initial whitespace
        for(uint i = 0; i < buffer.length; i++)
        {
            if(buffer[i] != ' ' && buffer[i] != '\t')
            {
                static if(H.SupportPartialData)
                {
                    parser.headerValueState = SaveHeaderValueState.noNewline;
                }
                parser.nextParse = &parseHeaderValue;
                parseHeaderValue(parser, buffer[i..$]);
                return;
            }
        }
    }
    private final void parseHeaderValue(HttpParser* parser, H.DataType[] buffer)
    {
        static if(H.SupportPartialData)
        {
            final switch(parser.headerValueState)
            {
                case SaveHeaderValueState.noNewline:
                    break;
                case SaveHeaderValueState.carriageReturn:
                    if(buffer.length == 0)
                    {
                        return;
                    }
                    if(buffer[0] == '\n')
                    {
                        parser.headerValueState = SaveHeaderValueState.lineFeed;
                        buffer = buffer[1..$];
                        goto case SaveHeaderValueState.lineFeed;
                    }
                    // TODO: pass in the original buffer, not a string
                    mixin(genCallbackCode(`H.onHeaderValuePartial(parser, cast(const(H.DataType)[])"\r")`));
                    parser.headerValueState = SaveHeaderValueState.noNewline;
                    break;
                case SaveHeaderValueState.lineFeed:
                    if(buffer.length == 0)
                    {
                        return;
                    }
                    if(buffer[0] != ' ' && buffer[0] != '\t')
                    {
                        // header value was already finished
                        mixin(genCallbackCode(`H.onHeaderValue(parser, null)`));
                        parser.nextParse = &initialParseHeaderName;
                        initialParseHeaderName(parser, buffer);
                        return;
                    }
                    // TODO: pass in the original buffer, not a string
                    mixin(genCallbackCode(`H.onHeaderValuePartial(parser, cast(const(H.DataType)[])"\r\n")`));
                    parser.headerValueState = SaveHeaderValueState.noNewline;
                    break;
            }

            assert(parser.headerValueState == SaveHeaderValueState.noNewline);
        }

        for(uint i = 0; i + 2 < buffer.length; i++)
        {
            if('\r' == buffer[i + 0] &&
               '\n' == buffer[i + 1] &&
              (' '  != buffer[i + 2] && '\t' != buffer[i + 2]))
            {
                mixin(genCallbackCode(`H.onHeaderValue(parser, buffer[0..i])`));
                parser.nextParse = &initialParseHeaderName;
                initialParseHeaderName(parser, buffer[i + 2..$]);
                return;
            }
            /*
            TODO: maybe check for valid characters and maybe a maximum header value
            if(!validTokenChar(buffer[i]))
            {
                H.onBadRequest(parser, HttpBadRequestReason.invalidHeaderNameCharacter);
                parser.nextParse = &parseInvalidState;
                return;
            }
            if(i >= H.MaximumHeaderName)
            {
                H.onBadRequest(parser, HttpBadRequestReason.headerNameTooLong);
                parser.nextParse = &parseInvalidState;
                return;
            }
            */
        }

        static if(H.SupportPartialData)
        {
            assert(parser.headerValueState == SaveHeaderValueState.noNewline);

            if(buffer.length > 0)
            {
                ubyte saved;
                if(buffer[$-1] == '\r')
                {
                    saved = 1;
                    parser.headerValueState = SaveHeaderValueState.carriageReturn;
                }
                else if(buffer.length >= 2 && buffer[$-1] == '\n' && buffer[$-2] == '\r')
                {
                    saved = 2;
                    parser.headerValueState = SaveHeaderValueState.lineFeed;
                }
                else
                {
                    saved = 0;
                }
                if(buffer.length > saved)
                {
                    mixin(genCallbackCode(`H.onHeaderValuePartial(parser, buffer[0..$-saved])`));
                }
            }
        }
        else
        {
            assert(0, "partial data unsupported");
        }
    }
}

enum CharacterFlags : ubyte
{
    none,
    ctl       = 1 << 0,
    separator = 1 << 1,
}
__gshared immutable CharacterFlags[128] characterFlagTable = [
    '\0'   : CharacterFlags.ctl,
    '\x01' : CharacterFlags.ctl,
    '\x02' : CharacterFlags.ctl,
    '\x03' : CharacterFlags.ctl,
    '\x04' : CharacterFlags.ctl,
    '\x05' : CharacterFlags.ctl,
    '\x06' : CharacterFlags.ctl,
    '\x07' : CharacterFlags.ctl,
    '\x08' : CharacterFlags.ctl,
    '\t'   : cast(CharacterFlags)(CharacterFlags.ctl | CharacterFlags.separator),
    '\n'   : CharacterFlags.ctl,
    '\x0B' : CharacterFlags.ctl,
    '\x0C' : CharacterFlags.ctl,
    '\r'   : CharacterFlags.ctl,
    '\x0E' : CharacterFlags.ctl,
    '\x0F' : CharacterFlags.ctl,
    '\x11' : CharacterFlags.ctl,
    '\x12' : CharacterFlags.ctl,
    '\x13' : CharacterFlags.ctl,
    '\x14' : CharacterFlags.ctl,
    '\x15' : CharacterFlags.ctl,
    '\x16' : CharacterFlags.ctl,
    '\x17' : CharacterFlags.ctl,
    '\x18' : CharacterFlags.ctl,
    '\x19' : CharacterFlags.ctl,
    '\x1A' : CharacterFlags.ctl,
    '\x1B' : CharacterFlags.ctl,
    '\x1C' : CharacterFlags.ctl,
    '\x1D' : CharacterFlags.ctl,
    '\x1E' : CharacterFlags.ctl,
    '\x1F' : CharacterFlags.ctl,
    ' '    : CharacterFlags.separator,
    '!'    : CharacterFlags.none,
    '"'    : CharacterFlags.separator,
    '#'    : CharacterFlags.none,
    '$'    : CharacterFlags.none,
    '%'    : CharacterFlags.none,
    '&'    : CharacterFlags.none,
    '\''   : CharacterFlags.none,
    '('    : CharacterFlags.separator,
    ')'    : CharacterFlags.separator,
    '*'    : CharacterFlags.none,
    '+'    : CharacterFlags.none,
    ','    : CharacterFlags.separator,
    '-'    : CharacterFlags.none,
    '.'    : CharacterFlags.none,
    '/'    : CharacterFlags.separator,
    '0'    : CharacterFlags.none,
    '1'    : CharacterFlags.none,
    '2'    : CharacterFlags.none,
    '3'    : CharacterFlags.none,
    '4'    : CharacterFlags.none,
    '5'    : CharacterFlags.none,
    '6'    : CharacterFlags.none,
    '7'    : CharacterFlags.none,
    '8'    : CharacterFlags.none,
    '9'    : CharacterFlags.none,
    ':'    : CharacterFlags.separator,
    ';'    : CharacterFlags.separator,
    '<'    : CharacterFlags.separator,
    '='    : CharacterFlags.separator,
    '>'    : CharacterFlags.separator,
    '?'    : CharacterFlags.separator,
    '@'    : CharacterFlags.separator,
    'A'    : CharacterFlags.none,
    'B'    : CharacterFlags.none,
    'C'    : CharacterFlags.none,
    'D'    : CharacterFlags.none,
    'E'    : CharacterFlags.none,
    'F'    : CharacterFlags.none,
    'G'    : CharacterFlags.none,
    'H'    : CharacterFlags.none,
    'I'    : CharacterFlags.none,
    'J'    : CharacterFlags.none,
    'K'    : CharacterFlags.none,
    'L'    : CharacterFlags.none,
    'M'    : CharacterFlags.none,
    'N'    : CharacterFlags.none,
    'O'    : CharacterFlags.none,
    'P'    : CharacterFlags.none,
    'Q'    : CharacterFlags.none,
    'R'    : CharacterFlags.none,
    'S'    : CharacterFlags.none,
    'T'    : CharacterFlags.none,
    'U'    : CharacterFlags.none,
    'V'    : CharacterFlags.none,
    'W'    : CharacterFlags.none,
    'X'    : CharacterFlags.none,
    'Y'    : CharacterFlags.none,
    'Z'    : CharacterFlags.none,
    '['    : CharacterFlags.separator,
    '\\'   : CharacterFlags.separator,
    ']'    : CharacterFlags.separator,
    '^'    : CharacterFlags.none,
    '_'    : CharacterFlags.none,
    '`'    : CharacterFlags.none,
    'a'    : CharacterFlags.none,
    'b'    : CharacterFlags.none,
    'c'    : CharacterFlags.none,
    'd'    : CharacterFlags.none,
    'e'    : CharacterFlags.none,
    'f'    : CharacterFlags.none,
    'g'    : CharacterFlags.none,
    'h'    : CharacterFlags.none,
    'i'    : CharacterFlags.none,
    'j'    : CharacterFlags.none,
    'k'    : CharacterFlags.none,
    'l'    : CharacterFlags.none,
    'm'    : CharacterFlags.none,
    'n'    : CharacterFlags.none,
    'o'    : CharacterFlags.none,
    'p'    : CharacterFlags.none,
    'q'    : CharacterFlags.none,
    'r'    : CharacterFlags.none,
    's'    : CharacterFlags.none,
    't'    : CharacterFlags.none,
    'u'    : CharacterFlags.none,
    'v'    : CharacterFlags.none,
    'w'    : CharacterFlags.none,
    'x'    : CharacterFlags.none,
    'y'    : CharacterFlags.none,
    'z'    : CharacterFlags.none,
    '{'    : CharacterFlags.separator,
    '|'    : CharacterFlags.none,
    '}'    : CharacterFlags.separator,
    '~'    : CharacterFlags.none,
    '\x7F' : CharacterFlags.none,
];

pragma(inline)
auto lookupCharacterFlags(char c)
{
    return (c <= 127) ? characterFlagTable[c] : CharacterFlags.ctl;
}
pragma(inline)
bool validTokenChar(char c)
{
    return 0 == (lookupCharacterFlags(c) & (CharacterFlags.ctl | CharacterFlags.separator));
}
version(unittest)
{
    import std.stdio;
    import std.format;
    import more.common;
    enum NextHttpCallback
    {
        method,
        uri,
        headerName,
        headerValue,
        done,
    }
    struct Header
    {
        string name;
        string value;
    }
    static struct ExpectedData
    {
        string expectedMethod;
        string expectedUri;
        Header[] expectedHeaders;

        bool expectingBadRequest;
        HttpBadRequestReason expectedBadRequest;
        bool gotBadRequest;

        NextHttpCallback nextCallback;
        uint nextHeaderIndex;
        uint currentDataOffset;

        this(string expectedMethod, string expectedUri, Header[] expectedHeaders...)
        {
            this.expectedMethod = expectedMethod;
            this.expectedUri = expectedUri;
            this.expectedHeaders = expectedHeaders;
            this.expectingBadRequest = false;
        }
        this(HttpBadRequestReason expectedBadRequest)
        {
            this.expectingBadRequest = true;
            this.expectedBadRequest = expectedBadRequest;
        }


        void reset()
        {
            this.nextCallback = NextHttpCallback.method;
            this.currentDataOffset = 0;
        }
        void allDataHasBeenGiven()
        {
            if(expectingBadRequest)
            {
                assert(gotBadRequest);
            }
            else
            {
                assert(nextCallback == NextHttpCallback.done);
            }
        }
        void onBadRequest(HttpBadRequestReason reason)
        {
            assert(expectingBadRequest);
            assert(!gotBadRequest);
            gotBadRequest = true;
            assert(expectedBadRequest == reason);
        }
        void onMethodPartial(T)(const(T)[] method)
        {
            assert(nextCallback == NextHttpCallback.method);
            if(!expectingBadRequest)
            {
                assert(expectedMethod[currentDataOffset..currentDataOffset + method.length] == method[]);
                currentDataOffset += method.length;
            }
        }
        void onMethod(T)(const(T)[] method)
        {
            assert(nextCallback == NextHttpCallback.method);
            if(!expectingBadRequest)
            {
                assert(expectedMethod[currentDataOffset..$] == method[],
                    format("expected \"%s\", got \"%s\"", expectedMethod[currentDataOffset..$], method));
            }
            nextCallback = NextHttpCallback.uri;
            currentDataOffset = 0;
        }
        void onUriPartial(T)(const(T)[] uri)
        {
            assert(nextCallback == NextHttpCallback.uri);
            if(!expectingBadRequest)
            {
                assert(expectedUri[currentDataOffset..currentDataOffset + uri.length] == uri[]);
                currentDataOffset += uri.length;
            }
        }
        void onUri(T)(const(T)[] uri)
        {
            assert(nextCallback == NextHttpCallback.uri);
            if(!expectingBadRequest)
            {
                assert(expectedUri[currentDataOffset..$] == uri[]);
            }
            if(expectedHeaders.length > 0)
            {
                nextCallback = NextHttpCallback.headerName;
            }
            else
            {
                nextCallback = NextHttpCallback.done;
            }
            currentDataOffset = 0;
        }

        void onHeaderNamePartial(T)(const(T)[] headerName)
        {
            assert(nextCallback == NextHttpCallback.headerName);
            if(!expectingBadRequest)
            {
                assert(expectedHeaders[nextHeaderIndex].name[currentDataOffset..currentDataOffset + headerName.length] == headerName[]);
                currentDataOffset += headerName.length;
            }
        }
        void onHeaderName(T)(const(T)[] headerName)
        {
            assert(nextCallback == NextHttpCallback.headerName);
            if(!expectingBadRequest)
            {
                assert(expectedHeaders[nextHeaderIndex].name[currentDataOffset..$] == headerName[]);
            }
            nextCallback = NextHttpCallback.headerValue;
            currentDataOffset = 0;
        }
        void onHeaderValuePartial(T)(const(T)[] value)
        {
            assert(nextCallback == NextHttpCallback.headerValue);
            if(!expectingBadRequest)
            {
                assert(expectedHeaders[nextHeaderIndex].value[currentDataOffset..currentDataOffset + value.length] == value[],
                    format("expected \"%s\" got \"%s\"", Escaped(expectedHeaders[nextHeaderIndex].value[currentDataOffset..currentDataOffset + value.length]), Escaped(value)));
                currentDataOffset += value.length;
            }
        }
        void onHeaderValue(T)(const(T)[] value)
        {
            assert(nextCallback == NextHttpCallback.headerValue);
            if(!expectingBadRequest)
            {
                assert(expectedHeaders[nextHeaderIndex].value[currentDataOffset..$] == value[],
                    format("expected \"%s\" got \"%s\"",
                    Escaped(expectedHeaders[nextHeaderIndex].value[currentDataOffset..$]), Escaped(value)));
            }
            nextHeaderIndex++;
            if(nextHeaderIndex >= expectedHeaders.length)
            {
                nextCallback = NextHttpCallback.done;
            }
            else
            {
                nextCallback = NextHttpCallback.headerName;
            }
            currentDataOffset = 0;
        }
        void onHeadersDone(T)(const(T)[] bodyData)
        {
            assert(nextCallback == NextHttpCallback.done);
            assert(nextHeaderIndex == expectedHeaders.length);
        }
    }
}
unittest
{
    import more.test;
    mixin(scopedTest!"httpparser");

    static void test(H)(HttpParser!H parser, ExpectedData expected, const(char)[] request)
    {
        if(H.SupportPartialData)
        {
            foreach(chunkLength; 1..request.length-1)
            {
                parser.reset();
                parser.expected = expected;
                size_t offset = 0;
                for(; offset + chunkLength <= request.length; offset += chunkLength)
                {
                    //writefln("parsing \"%s\"", Escaped(request[offset..offset + chunkLength]));
                    parser.parse(request[offset..offset + chunkLength]);
                }
                if(offset < request.length)
                {
                    //writefln("parsing \"%s\"", Escaped(request[offset..$]));
                    parser.parse(request[offset..$]);
                }
                parser.expected.allDataHasBeenGiven();
            }
        }

        parser.expected.reset();
        parser.reset();
        parser.expected = expected;
        //writefln("parsing \"%s\"", Escaped(request));
        parser.parse(request);
        parser.expected.allDataHasBeenGiven();
    }

    static struct Hooks1
    {
        alias DataType = const(char);

        // Note: maximum are meant to stop bad data earlier on, they do not increase memory usage
        enum MaximumMethodName = 30;
        enum MaximumHeaderName = 40;

        enum SupportPartialData = false;
        enum SupportCallbackStop = false;
        mixin template HttpParserMixinTemplate()
        {
            ExpectedData expected;
        }
        static void onBadRequest(HttpParser!Hooks1* parser, HttpBadRequestReason reason)
        {
            parser.expected.onBadRequest(reason);
        }
        static void onMethod(HttpParser!Hooks1* parser, DataType[] method)
        {
            parser.expected.onMethod(method);
        }
        static void onUri(HttpParser!Hooks1* parser, DataType[] uri)
        {
            parser.expected.onUri(uri);
        }
        static void onHeaderName(HttpParser!Hooks1* parser, DataType[] headerName)
        {
            parser.expected.onHeaderName(headerName);
        }
        static void onHeaderValue(HttpParser!Hooks1* parser, DataType[] value)
        {
            parser.expected.onHeaderValue(value);
        }
        static void onHeadersDone(HttpParser!Hooks1* parser, DataType[] bodyData)
        {
            parser.expected.onHeadersDone(bodyData);
        }
    }
    static struct Hooks2
    {
        alias DataType = const(char);

        // Note: maximum are meant to stop bad data earlier on, they do not increase memory usage
        enum MaximumMethodName = 30;
        enum MaximumHeaderName = 40;

        enum SupportPartialData = true;
        enum SupportCallbackStop = false;
        mixin template HttpParserMixinTemplate()
        {
            ExpectedData expected;
        }
        static void onBadRequest(HttpParser!Hooks2* parser, HttpBadRequestReason reason)
        {
            parser.expected.onBadRequest(reason);
        }
        static void onMethodPartial(HttpParser!Hooks2* parser, DataType[] method)
        {
            parser.expected.onMethodPartial(method);
        }
        static void onMethod(HttpParser!Hooks2* parser, DataType[] method)
        {
            parser.expected.onMethod(method);
        }
        static void onUriPartial(HttpParser!Hooks2* parser, DataType[] uri)
        {
            parser.expected.onUriPartial(uri);
        }
        static void onUri(HttpParser!Hooks2* parser, DataType[] uri)
        {
            parser.expected.onUri(uri);
        }
        static void onHeaderNamePartial(HttpParser!Hooks2* parser, DataType[] headerName)
        {
            parser.expected.onHeaderNamePartial(headerName);
        }
        static void onHeaderName(HttpParser!Hooks2* parser, DataType[] headerName)
        {
            parser.expected.onHeaderName(headerName);
        }
        static void onHeaderValuePartial(HttpParser!Hooks2* parser, DataType[] value)
        {
            parser.expected.onHeaderValuePartial(value);
        }
        static void onHeaderValue(HttpParser!Hooks2* parser, DataType[] value)
        {
            parser.expected.onHeaderValue(value);
        }
        static void onHeadersDone(HttpParser!Hooks2* parser, DataType[] bodyData)
        {
            parser.expected.onHeadersDone(bodyData);
        }
    }
    // TODO: add tests to make sure the SupportCallbackStop works properly
    static struct Hooks3
    {
        alias DataType = char;

        // Note: maximum are meant to stop bad data earlier on, they do not increase memory usage
        enum MaximumMethodName = 30;
        enum MaximumHeaderName = 40;

        enum SupportPartialData = true;
        enum SupportCallbackStop = true;
        mixin template HttpParserMixinTemplate()
        {
            ExpectedData expected;
        }
        static void onBadRequest(HttpParser!Hooks2* parser, HttpBadRequestReason reason)
        {
            parser.expected.onBadRequest(reason);
        }
        static Flag!"stop" onMethodPartial(HttpParser!Hooks2* parser, DataType[] method)
        {
            parser.expected.onMethodPartial(method);
            return No.stop;
        }
        static Flag!"stop" onMethod(HttpParser!Hooks2* parser, DataType[] method)
        {
            parser.expected.onMethod(method);
            return No.stop;
        }
        static Flag!"stop" onUriPartial(HttpParser!Hooks2* parser, DataType[] uri)
        {
            parser.expected.onUriPartial(uri);
            return No.stop;
        }
        static Flag!"stop" onUri(HttpParser!Hooks2* parser, DataType[] uri)
        {
            parser.expected.onUri(uri);
            return No.stop;
        }
        static Flag!"stop" onHeaderNamePartial(HttpParser!Hooks2* parser, DataType[] headerName)
        {
            parser.expected.onHeaderNamePartial(headerName);
            return No.stop;
        }
        static Flag!"stop" onHeaderName(HttpParser!Hooks2* parser, DataType[] headerName)
        {
            parser.expected.onHeaderName(headerName);
            return No.stop;
        }
        static Flag!"stop" onHeaderValuePartial(HttpParser!Hooks2* parser, DataType[] value)
        {
            parser.expected.onHeaderValuePartial(value);
            return No.stop;
        }
        static Flag!"stop" onHeaderValue(HttpParser!Hooks2* parser, DataType[] value)
        {
            parser.expected.onHeaderValue(value);
            return No.stop;
        }
        static void onHeadersDone(HttpParser!Hooks2* parser, DataType[] bodyData)
        {
            parser.expected.onHeadersDone(bodyData);
        }
    }

    template tuple(T...)
    {
        alias tuple = T;
    }
    foreach(hooks; tuple!(Hooks1, Hooks2))
    {
        auto parser = HttpParser!hooks();

        // invalid method character
        foreach(c; '\0'..'\x7F')
        {
            if(c.validTokenChar || c == ' ')
            {
                continue;
            }
            {
                parser.reset();
                char[2] method;
                method[0] = c;
                method[1] = ' ';
                parser.expected = ExpectedData(HttpBadRequestReason.invalidMethodCharacter);
                parser.parse(method);
            }
            {
                parser.reset();
                char[5] method;
                method[0..3] = "GET";
                method[3] = c;
                method[4] = ' ';
                parser.expected = ExpectedData(HttpBadRequestReason.invalidMethodCharacter);
                parser.parse(method);
            }
        }
        // method name too long
        {
            parser.reset();
            char[hooks.MaximumMethodName + 1] method;
            method[] = 'A';
            parser.expected = ExpectedData(HttpBadRequestReason.methodNameTooLong);
            parser.parse(method);
        }

        // bad http version
        foreach(badHttpVersion; [
            "GET /index.html HTTP/1.1\r\r",
            "GET /index.html HTTP/1.0\r\n",
            "GET /index.html !TTP/1.0\r\n",
        ])
        {
            parser.reset();
            parser.expected = ExpectedData(HttpBadRequestReason.badHttpVersion);
            writefln("test \"%s\"", Escaped(badHttpVersion));
            parser.parse(badHttpVersion);
            parser.expected.allDataHasBeenGiven();
        }

        test(parser, ExpectedData("GET", "/index.html"), "GET /index.html HTTP/1.1\r\n\r\n");
        test(parser, ExpectedData("POST", "12345678901234567890__________1234567890fdjadjakljflda"),
            "POST 12345678901234567890__________1234567890fdjadjakljflda HTTP/1.1\r\n\r\n");

        test(parser, ExpectedData("GET", "/index.html", Header("Host", "www.google.com")),
            "GET /index.html HTTP/1.1\r\nHost: www.google.com\r\n\r\n");
        test(parser, ExpectedData("GET", "/index.html", Header("Host", "www.google.com\r\n hi")),
            "GET /index.html HTTP/1.1\r\nHost: www.google.com\r\n hi\r\n\r\n");
        test(parser, ExpectedData("GET", "/index.html", Header("Host", "www.google.com\r\r")),
            "GET /index.html HTTP/1.1\r\nHost: www.google.com\r\r\r\n\r\n");
    }
}