module more.esb.parser;

import std.array : Appender;
import std.format : format;
import std.conv : to;
import std.algorithm : startsWith;

import more.format : utf8WriteEscaped;
import more.utf8 : decodeUtf8;

/// Identifies the type of an $(D Expression).
enum ExpressionType : ubyte
{
    /**
    A "symbol" expression is a sequence of characters that match the following regex:
        [a-zA-Z_/\.][a-zA-Z_/\.0-9]*
    TODO: this regex should probably be configurable by the application.
    */
    symbol,
    /**
    A string is a sequence of character surrounded by "double-quotes".
    Might add more types of strings later.  The types of strings could
    also be configurable by the application.
    */
    string_,
    functionCall,
}

struct FunctionCall
{
    size_t sourceNameLength;
    Expression[] args;
}

struct Expression
{
    union
    {
        // Note: the "string_" field may or may not be a slice of "source"
        // If it is a symbol, then it MUST be equal to source.
        // TODO: I think I want to change this, DO NOT USE string_ for if it is a symbol.
        // If it is a string_, then source will be the full quoted source string, and string_
        // will be the source without the quotes if there are no escapes, otherwise, it will
        // be a new string outside the source with the escapes handled.
        string string_;
        FunctionCall functionCall;
    }
    string source;
    ExpressionType type;
    private this(string source, ExpressionType type, string string_)
    {
        this.source = source;
        this.type = type;
        this.string_ = string_;
    }
    private this(string source, FunctionCall functionCall)
    {
        this.source = source;
        this.type = ExpressionType.functionCall;
        this.functionCall = functionCall;
    }

    static Expression createSymbol(string source)
    {
        return Expression(source, ExpressionType.symbol, source);
    }
    static Expression createString(string source, string processedString)
    {
        return Expression(source, ExpressionType.string_, processedString);
    }
    static Expression createFunctionCall(string source, string name, Expression[] args)
    {
        assert(source.ptr == name.ptr);
        return Expression(source, FunctionCall(name.length, args));
    }

    @property string functionName() const
        in { assert(type == ExpressionType.functionCall); } body
    {
        return source[0 .. functionCall.sourceNameLength];
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink(source);
    }
}

/**
A Statement is one of the 3 building blocks for ESB. It represents
a list of expressions followed by an optional block of statements.
*/
struct Statement
{
    private Expression[] expressions;
    Statement[] block;
    @property auto expressionCount() { return expressions.length; }
    @property auto expressionAt(size_t index) { return expressions[index];}
    auto range(size_t expressionOffset)
        in { assert(expressionOffset <= expressions.length); } body
    {
        return StatementRangeReference(&this, expressionOffset);
    }
    @property immutable(char)* sourceStart()
    {
        if(expressions.length > 0)
        {
            return expressions[0].source.ptr;
        }
        // TODO: implement this
        assert(0, "not implemented");
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        string prefix = "";
        foreach(expression; expressions)
        {
            sink(prefix);
            sink(expression.source);
            prefix = " ";
        }
        if(block is null)
        {
            sink(";");
        }
        else
        {
            sink("{");
            foreach(property; block)
            {
                property.toString(sink);
            }
            sink("}");
        }
    }
}

/**
This struct is used to represent a partial statement by skipping over
a number of expressions. It can be created from a $(D Statement) by calling
statement.range(expressionOffset).
*/
struct StatementRangeReference
{
    Statement* statement;
    size_t next;
    @property auto expressionsLeft() { return statement.expressions[next..$]; }
    @property auto expressionAt(size_t index) { return statement.expressions[next + index];}
    @property auto block() { return statement.block; }

    auto range(size_t expressionOffset)
    {
        return StatementRangeReference(statement, next + expressionOffset);
    }
    @property immutable(char)* sourceStart()
    {
        // TODO: maybe use next to offset the start?
        return statement.sourceStart();
    }

    @property bool empty() { return next >= statement.expressions.length; }
    auto front()
    {
        return statement.expressions[next];
    }
    void popFront() { next++; }
    @property final size_t remainingValues()
    {
        return statement.expressions.length - next;
    }
}

/**
The default NodeBuilder implementation.  A NodeBuilder is used to allocate
memory for lists of $(D Statement) and $(D Expression). The parser requires
a NodeBuilder to be accessible via it's template parameter as the "NodeBuilder" field.
*/
struct DefaultNodeBuilder
{
    static struct BlockBuilder
    {
        Appender!(Statement[]) appender;
        this(size_t depth)
        {
        }
        void newStatement(Expression[] expressions, Statement[] block)
        {
            appender.put(Statement(expressions, block));
        }
        auto finish()
        {
            return appender.data;
        }
    }
    static struct ExpressionBuilder
    {
        Expression[10] firstValues;
        Appender!(Expression[]) extraValues;
        ubyte state;
        void append(Expression expression)
        {
            if(state < firstValues.length)
            {
                firstValues[state++] = expression;
            }
            else
            {
                if(state == firstValues.length)
                {
                    extraValues.put!(Expression[])(firstValues);
                    state++;
                }
                extraValues.put(expression);
            }
        }
        auto finish()
        {
            if(state == 0)
            {
                return null;
            }
            else if(state <= firstValues.length)
            {
                return firstValues[0..state].dup;
            }
            else
            {
                return extraValues.data;
            }
        }
    }
}

/**
The default set of hooks for the ESB Parser
*/
struct DefaultEsbParserHooks
{
    alias NodeBuilder = DefaultNodeBuilder;
    enum StatementDelimiter = ';';
}


class ParseException : Exception
{
    this(string msg, string filename, uint lineNumber)
    {
        super(msg, filename, lineNumber);
    }
}

static struct PeekedChar
{
    dchar nextChar;
    const(char)* nextNextPtr;
}
private bool validNameFirstChar(dchar c)
{
    return
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c == '_') ||
        (c == '.') ||
        (c == '/');
}
private bool validNameChar(dchar c)
{
    return
        validNameFirstChar(c) ||
        (c >= '0' && c <= '9');
}

/**
NOTE: text must be null-terminated
*/
auto parse(Hooks = DefaultEsbParserHooks)(string text, string filenameForErrors = null, uint lineNumber = 1)
{
    auto parser = Parser!Hooks(text.ptr, filenameForErrors, lineNumber);
    return parser.parse();
}
struct Parser(Hooks)
{
    immutable(char)* nextPtr;
    dchar current;
    immutable(char)* currentPtr;
    string filenameForErrors;
    uint lineNumber;
    
    this(immutable(char)* nextPtr, string filenameForErrors = null, uint lineNumber = 1)
    {
        this.nextPtr = nextPtr;
        this.filenameForErrors = filenameForErrors;
        this.lineNumber = lineNumber;
    }

    auto parseException(T...)(string fmt, T args)
    {
        return new ParseException(format(fmt, args), filenameForErrors, lineNumber);
    }

    Statement[] parse()
    {
        // read the first character
        consumeChar();
        return parseBlock(0);
    }
    private Statement[] parseBlock(size_t depth)
    {
        auto blockBuilder = Hooks.NodeBuilder.BlockBuilder(depth);

        for(;;)
        {
            // parse optional expressions
            Expression[] expressions;
            {
                auto expressionBuilder = Hooks.NodeBuilder.ExpressionBuilder();
                for(;;)
                {
                    auto expression = tryPeelExpression();
                    if(expression.source is null)
                    {
                        break;
                    }
                    expressionBuilder.append(expression);
                }
                expressions = expressionBuilder.finish();
            }

            if(expressions.length == 0)
            {
                if(current == '\0')
                {
                    if(depth == 0)
                    {
                        break;
                    }
                    throw parseException("not enough closing curly-braces");
                }
                if(current == '}')
                {
                    if(depth == 0)
                    {
                        throw parseException("too many closing curly-braces");
                    }
                    consumeChar();
                    break;
                }
                if(current == '{')
                {
                    consumeChar();
                    blockBuilder.newStatement(null, parseBlock(depth + 1));
                }
                else
                {
                    throw parseException("expected an expression, or a '{ block }' but got %s", formatToken(currentPtr));
                }
            }
            else
            {
                if(current == Hooks.StatementDelimiter)
                {
                    consumeChar();
                    blockBuilder.newStatement(expressions, null);
                }
                else if(current == '{')
                {
                    consumeChar();
                    blockBuilder.newStatement(expressions, parseBlock(depth + 1));
                }
                else
                {
                    throw parseException("expected statement to end with '" ~
                        Hooks.StatementDelimiter ~ "' or '{ block }' but got %s", formatToken(currentPtr));
                }
            }
        }
        return blockBuilder.finish();
    }
    pragma(inline) void consumeChar()
    {
        currentPtr = nextPtr;
        current = decodeUtf8(&nextPtr);
    }
    // NOTE: only call if you know you are not currently pointing to the
    //       terminating NULL character
    const PeekedChar peek() in { assert(current != '\0'); } body
    {
        PeekedChar peeked;
        peeked.nextNextPtr = nextPtr;
        peeked.nextChar = decodeUtf8(&peeked.nextNextPtr);
        return peeked;
    }

    void skipToNextLine()
    {
        for(;;)
        {
            auto c = decodeUtf8(&nextPtr);
            if(c == '\n')
            {
                lineNumber++;
                return;
            }
            if(c == '\0')
            {
                currentPtr = nextPtr;
                current = '\0';
                return;
            }
        }
    }
    void skipWhitespaceAndComments()
    {
        for(;;)
        {
            if(current == ' ' || current == '\t' || current == '\r')
            {
                //do nothing
            }
            else if(current == '\n')
            {
                lineNumber++;
            }
            else if(current == '/')
            {
                auto next = peek(); // Note: we know current != '\0'
                if(next.nextChar == '/')
                {
                    skipToNextLine();
                    if(current == '\0')
                    {
                        return;
                    }
                }
                else if(next.nextChar == '*')
                {
                    assert(0, "multiline comments not implemented");
                }
                else
                {
                    return; // not a whitespace or comment
                }
            }
            else
            {
                return; // not a whitespace or comment
            }
            consumeChar();
        }
    }
    auto tryPeelName()
    {
        skipWhitespaceAndComments();
        if(!validNameFirstChar(current))
        {
            return null;
        }
        auto nameStart = currentPtr;
        for(;;)
        {
            consumeChar();
            if(!validNameChar(current))
            {
                return nameStart[0..currentPtr-nameStart];
            }
        }
    }


    Expression tryPeelExpression()
    {
        for(;;)
        {
            Expression part = tryPeelExpressionLevel0();
            if(part.source is null)
            {
                return part;
            }
            skipWhitespaceAndComments();
            // TODO: check for operations such as '+' etc
            return part;
        }
    }
    // Level 0 expressions are the expressions with the highest operator precedence.
    // 1) symbol
    // 2) function call (symbol '(' args.. ')')
    // 3) string
    Expression tryPeelExpressionLevel0()
    {
        skipWhitespaceAndComments();
        if(validNameFirstChar(current))
        {
            auto nameStart = currentPtr;
            for(;;)
            {
                consumeChar();
                if(!validNameChar(current))
                {
                    auto name = nameStart[0..currentPtr-nameStart];
                    skipWhitespaceAndComments();
                    if(current == '(')
                    {
                        return peelFunctionCall(name);
                    }
                    return Expression.createSymbol(name);
                }
            }
        }
        if(current == '"')
        {
            return peelString();
        }
        return Expression(); // no level0 expression was found
    }
    // Assumption: current is at the opening quote
    Expression peelString()
    {
        auto start = currentPtr;
        immutable(char)* firstEscape = null;
        for(;;)
        {
            consumeChar();
            if(current == '"')
            {
                break;
            }
            if(current == '\\')
            {
                if(!firstEscape)
                {
                    firstEscape = currentPtr;
                }
                assert(0, "escapes not implemented");
            }
            else if(current == '\n')
            {
                // TODO: maybe provide a way to allow this
                throw parseException("double-quoted strings cannot contain newlines");
            }
            else if(current == '\0')
            {
                throw parseException("file ended inside double-quoted string");
            }
        }
        if(!firstEscape)
        {
            consumeChar();
            auto source = start[0 .. currentPtr - start];
            auto str = source[1..$-1];
            return Expression.createString(source, str);
        }
        assert(0, "escapes not implemented");
    }
    // Assumption: current points to opening paren
    Expression peelFunctionCall(string name)
    {
        auto sourceStart = name.ptr;
        auto expressionBuilder = Hooks.NodeBuilder.ExpressionBuilder();

        consumeChar();
        skipWhitespaceAndComments();
        if(current != ')')
        {
            for(;;)
            {
                auto expression = tryPeelExpression();
                if(expression.source is null)
                {
                    throw parseException("expected function call to end with ')' but got '%s'", formatToken(currentPtr));
                }
                expressionBuilder.append(expression);
                skipWhitespaceAndComments();
                if(current == ')')
                {
                    break;
                }
                if(current != ',')
                {
                    throw parseException("expected comma ',' after function argument but got '%s'", formatToken(currentPtr));
                }
                consumeChar();
            }
        }
        consumeChar();
        auto source = sourceStart[0 .. currentPtr - sourceStart];
        return Expression.createFunctionCall(source, name, expressionBuilder.finish());
    }
}
auto guessEndOfToken(const(char)* ptr)
{
    // TODO: should use the first char to determine the kind of token and
    //       then find the end using that information
    for(;;)
    {
        auto c = *ptr;
        if(c == '\0' || c == ' ' || c == '\t' || c == '\r' || c == '\n')
        {
            return ptr;
        }
        decodeUtf8(&ptr);
    }
}
auto formatToken(const(char)* token)
{
    static struct Formatter
    {
        const(char)* token;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            if(*token == '\0')
            {
                sink("EOF");
            }
            else
            {
                sink("\"");
                sink.utf8WriteEscaped(token, guessEndOfToken(token));
                sink("\"");
            }
        }
    }
    return Formatter(token);
}

version(unittest)
{
    static void assertEqual(Statement expected, Statement actual)
    {
        assert(expected.expressions.length == actual.expressions.length);

    }
    static void test(string text, Statement[] expected)
    {
        auto actual = parse(text);
        assert(actual.length == expected.length);
        foreach(statementIndex; 0..actual.length)
        {
            assertEqual(expected[statementIndex], actual[statementIndex]);
        }
    }
    static auto block(Statement[] statements...)
    {
        return statements.dup;
    }
    static auto statement(Expression[] expressions, Statement[] block = null)
    {
        return Statement(expressions, block);
    }
    static auto symbol(string name)
    {
        return Expression.createSymbol(name);
    }
}

unittest
{
    test("", null);
    test("a;", block(statement([symbol("a")])));
    test("a{}", block(statement([symbol("a")])));

    test(`abc
{
    def;
    hij;
}`, block(statement([symbol("abc")], block(
    Statement([symbol("def")]),
    Statement([symbol("hij")])
))));
}