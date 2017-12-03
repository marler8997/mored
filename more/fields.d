module more.fields;

import std.string;

import more.utf8;
import more.common;

version(unittest)
{
    import std.stdio;
}

class TextParseException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

struct Text
{
  uint lineNumber;
  uint column;

  const(char)[] chars;
  const(char)* limit;

  const(char)* cpos;
  const(char)* next;

  dchar c;

  this(const(char)[] chars) {
    setup(chars);
  }
  void setup(const(char)[] chars) {
    this.lineNumber = 1;
    this.column = 1;

    this.chars = chars;
    this.limit = chars.ptr + chars.length;
    this.cpos = chars.ptr;
    this.next = chars.ptr;

    if(chars.length > 0) {
      c = decodeUtf8(&this.next, this.limit);
    }
  }
  @property bool empty() {
    return cpos >= limit;
  }

  void skipChar() {
    cpos = next;
    if(next < limit) {
      c = decodeUtf8(&next, limit);
    }
  }

  void toNextLine()
  {
    while(true) {
      if(next >= limit) break;
      c = decodeUtf8(&next, limit);
      if(c == '\n') {
        lineNumber++;
        column = 1;
        break;
      }
    }
    cpos = next;
    if(next < limit) {
      c = decodeUtf8(&next, limit);
    }
  }
  void toNewline()
  {
    while(true) {
      cpos = next;
      if(next >= limit) break;
      c = decodeUtf8(&next, limit);
      column++;
      if(c == '\n') {
        break;
      }
    }
  }
  void toEndOfToken()
  {
    if(c == '"') {
      implement("quoted tokens");
    } else {

      while(true) {
        cpos = next;
        if(next >= limit) break;
        c = decodeUtf8(&next, limit);
        column++;
        if(isControlChar(c)) {

          // Handle slashes that aren't comments
          if(c != '/') break;
          if(next >= limit) {
            cpos = next;
            break;
          }
          auto saveNext = next;
          c = decodeUtf8(&next, limit);
          next = saveNext;

          if(c == '*' || c == '/') {
            break;
          }

        }

      }
    }
  }

  // If skipNewlines is true, c/cpos will be pointing at the newline if no field was found
  void skipWhitespaceAndComments(bool skipNewlines)
  {
    while(true) {

      // TODO: maybe use a lookup table here
      if(c == ' ' || c == '\t' || c =='\v' || c == '\f' || c == '\r') {

        // do nothing (check first as this is the most likely case)

      } else if(c == '\n') {

        if(!skipNewlines) return;

        lineNumber++;
        column = 1;

      } else if(c == '#') {

        if(!skipNewlines) {
          toNewline();
          return;
        }

        toNextLine();

      } else if(c == '/') {

        if(next >= limit) return;

        c = decodeUtf8(&next, limit);

        if(c == '/') {

          if(!skipNewlines) {
            toNewline();
            return;
          }

          toNextLine();

        } else if(c == '*') {

          if(!skipNewlines) {
            implement("multiline comments when not skipping newlines");
          }


          column++;

        MULTILINE_COMMENT_LOOP:
          while(next < limit) {

            c = decodeUtf8(&next, limit); // no need to save cpos since c will be thrown away
            column++;

            if(c == '\n') {
              lineNumber++;
              column = 0;
              lineNumber++;
            } else if(c == '*') {
              // loop assume c is pointing to a '*' and next is pointing to the next characer
              while(next < limit) {

                c = decodeUtf8(&next, limit);
                column++;
                if(c == '/') break MULTILINE_COMMENT_LOOP;
                if(c == '\n') {
                  lineNumber++;
                  column = 0;
                } else if(c != '*') {
                  break;
                }
              }
            }
          }

        } else {
          return;
        }

      } else {

        return; // Found non-whitespace and non-comment

      }

      //
      // Goto next character
      //
      cpos = next;
      if(next >= limit) return;
      c = decodeUtf8(&next, limit);
      column++;
    }

  }
  void parseField(ref FieldToken token, bool sameLine = false)
  {
    skipWhitespaceAndComments(!sameLine);
    if(cpos >= limit || (sameLine && c == '\n')) {
      token.text = null;
      token.lineNumber = lineNumber;
      token.column = column;
    } else {

      if(isControlChar(c)) {
        throw new TextParseException(format("Expected non-control character but got '%s' (charcode=%s)",
                                            c, cast(uint)c));
      }

      const(char)* startOfToken = cpos;
      token.lineNumber = lineNumber;
      token.column = column;
      toEndOfToken();
      token.text = startOfToken[0..cpos-startOfToken];
    }
  }
  bool noMoreFieldsOnThisLine()
  {
    skipWhitespaceAndComments(false);
    return cpos >= limit || c == '\n';
  }


  void parseString(ref FieldToken token)
  {
    skipWhitespaceAndComments(true);
    token.lineNumber = lineNumber;
    token.column = column;
    if(cpos >= limit || isControlChar(c)) {
      token.text = null;
    } else {
      const(char)* startOfToken = cpos;
      toEndOfToken();
      token.text = startOfToken[0..cpos-startOfToken];
    }
  }


  alias parseString parseObjectFieldName;

  // An object starts with an open curly brace '{' or omits its curly
  // brace section with a semi-colon ';'
  // A 'NamelessObjectField' is a field before the curly-brace section
  void parseNamelessObjectField(ref FieldToken token)
  {
    skipWhitespaceAndComments(true);
    token.lineNumber = lineNumber;
    token.column = column;
    if(cpos >= limit || isControlChar(c)) {
      token.text = null;
    } else {
      const(char)* startOfToken = cpos;
      toEndOfToken();
      token.text = startOfToken[0..cpos-startOfToken];
    }
  }
  bool atObjectStart()
  {
    skipWhitespaceAndComments(true);
    if(cpos >= limit || c != '{') return false;

    cpos = next;
    if(next < limit) {
      c = decodeUtf8(&next, limit);
    }
    return true;
  }
}


struct FieldToken
{
  const(char)[] text;
  uint lineNumber;
  uint column;

  bool eof()
  {
    return text is null;
  }
}

/+
/**
 * Used to parse the fields in <i>line</i> to the <i>fields</i> sink.
 * line is a single line without the line ending character.
 * returns error message on error
 */
void parseField(ref FieldToken token, ref Text text)
{
  //writefln("[DEBUG] parseField(..., '%s')", escape(text.chars));

  const(char)* next = text.chars.ptr;
  const char* limit = next + text.chars.length;
  const(char)* cpos;
  dchar c;

  // ExpectedState:
  //   c/cpos: points to a character before the newline character
  // ReturnState:
  //   c/cpos: points to the character after the newline character or at limit if at EOF
  void toNextLine()
  {
    // no need to save cpos since c will be thrown away
    while(true) {
      if(next >= limit) break;
      c = decodeUtf8(&next, limit);
      if(c == '\n') {
        text.lineNumber++;
        text.column = 1;
        break;
      }
    }
    cpos = next;
    if(next < limit) {
      c = decodeUtf8(&next, limit);
    }
  }
  // ExpectedState:
  //   c/cpos: points to the first character of the token
  // ReturnState:
  //   c/cpos: points to the character after the token
  void toEndOfToken()
  {
    if(c == '"') {
      implement("quoted tokens");
    } else {

      while(true) {
        cpos = next;
        if(next >= limit) break;
        c = decodeUtf8(&next, limit);
        text.column++;
        if(isControlChar(c)) {
          break;
        }
      }
    }
  }
  // ExpectedState:
  //   c/cpos: points to the first character of the potential whitespace/comment
  // ReturnState:
  //   c/cpos: points to the first character after all the whitespace/comments
  void skipWhitespaceAndComments()
  {
    while(true) {

      // TODO: maybe use a lookup table here
      if(c == ' ' || c == '\t' || c =='\v' || c == '\f' || c == '\r') {

        // do nothing (check first as this is the most likely case)

      } else if(c == '\n') {

        text.lineNumber++;
        text.column = 1;

      } else if(c == '#') {

        toNextLine();

      } else if(c == '/') {

        if(next >= limit) return;

        c = decodeUtf8(&next, limit);

        if(c == '/') {

          toNextLine();

        } else if(c == '*') {

          text.column++;

        MULTILINE_COMMENT_LOOP:
          while(next < limit) {

            c = decodeUtf8(&next, limit); // no need to save cpos since c will be thrown away
            text.column++;

            if(c == '\n') {
              text.lineNumber++;
              text.column = 0;
              text.lineNumber++;
            } else if(c == '*') {
              // loop assume c is pointing to a '*' and next is pointing to the next characer
              while(next < limit) {

                c = decodeUtf8(&next, limit);
                text.column++;
                if(c == '/') break MULTILINE_COMMENT_LOOP;
                if(c == '\n') {
                  text.lineNumber++;
                  text.column = 0;
                } else if(c != '*') {
                  break;
                }
              }
            }
          }

        } else {
          return;
        }

      } else {

        return; // Found non-whitespace and non-comment

      }

      //
      // Goto next character
      //
      cpos = next;
      if(next >= limit) return;
      c = decodeUtf8(&next, limit);
      text.column++;
    }

  }

  //
  // Read the first character
  //
  cpos = next;
  c = decodeUtf8(&next, limit);

  skipWhitespaceAndComments();
  if(cpos >= limit) {
    token.text = null;
    text.chars = null;
    return;
  }

  const(char)* startOfToken = cpos;
  token.lineNumber = text.lineNumber;
  token.column = text.column;
  toEndOfToken();
  token.text = startOfToken[0..cpos-startOfToken];

  text.chars = cpos[0..limit-cpos];

  return;
}
+/


enum ubyte controlCharFlag                  = 0x01;
enum ubyte whitespaceFlag                   = 0x02;
enum ubyte tokenStartFlag                   = 0x04;

bool isControlChar(dchar c) {
  return (c < charLookup.length) && ( (charLookup[c] & controlCharFlag) != 0);
}
bool isWhitespace(dchar c) {
  return (c < charLookup.length) && ( (charLookup[c] & whitespaceFlag) != 0);
}
mixin("private __gshared immutable ubyte[256] charLookup = "~rangeInitializers
      (
       /*
         "'_'"    , "sdlIDFlag",

         `'a'`    , "sdlIDFlag",
         `'b'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'c'`    , "sdlIDFlag",
         `'d'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'e'`    , "sdlIDFlag",
         `'f'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'g'-'k'`, "sdlIDFlag",
         `'l'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'m'-'z'`, "sdlIDFlag",

         `'A'`    , "sdlIDFlag",
         `'B'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'C'`    , "sdlIDFlag",
         `'D'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'E'`    , "sdlIDFlag",
         `'F'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'G'-'K'`, "sdlIDFlag",
         `'L'`    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
         `'M'-'Z'`, "sdlIDFlag",

         `'0'-'9'`, "sdlIDFlag | sdlNumberFlag",
         `'-'`    , "sdlIDFlag",
         `'.'`    , "sdlIDFlag | sdlNumberFlag",
         `'$'`    , "sdlIDFlag",
       */
       `' '`    , "controlCharFlag | whitespaceFlag",
       `'\t'`   , "controlCharFlag | whitespaceFlag",
       `'\n'`   , "controlCharFlag | whitespaceFlag",
       `'\v'`   , "controlCharFlag | whitespaceFlag",
       `'\f'`   , "controlCharFlag | whitespaceFlag",
       `'\r'`   , "controlCharFlag | whitespaceFlag",
       `'{'`    , "controlCharFlag",
       `'}'`    , "controlCharFlag",

       `'['`    , "controlCharFlag",
       `']'`    , "controlCharFlag",
       //`';'`    , "controlCharFlag",
       //`'\\'`    , "controlCharFlag",
       `'/'`    , "controlCharFlag",
       `'#'`    , "controlCharFlag",


       )~";");

unittest
{
  import more.test;
  mixin(scopedTest!"fields");

  writefln("Running Unit Tests...");

  void testParseFields(const(char)[] textString, FieldToken[] expectedTokens = [], size_t testLine = __LINE__)
  {
    auto escapedText = escape(textString);

    debug {
      writefln("[TEST] testing '%s'", escapedText);
    }

    FieldToken token;
    Text text = Text(textString);
    //text.setup(textString);

    try {

      for(auto i = 0; i < expectedTokens.length; i++) {

        //parseField(token, text);
        text.parseField(token);
        if(token.eof) {
          writefln("Expected %s token(s) but only got %s", expectedTokens.length, i);
          writefln("Error: test on line %s", testLine);
        }

        auto expectedToken = expectedTokens[i];
        if(token.text != expectedToken.text) {
          writefln("Error: expected token '%s' but got '%s'", expectedToken.text, token.text);
          writefln("Error: test on line %s", testLine);
          assert(0);
        }
      }

      //parseField(token, text);
      text.parseField(token);
      if(!token.eof) {
        writefln("Expected %s token(s) but got at least one more (text='%s')",
                 expectedTokens.length, token.text);
        writefln("Error: test on line %s", testLine);
        assert(0);
      }

    } catch(Exception e) {
      writefln("[TEST] this sdl threw an unexpected Exception: '%s'", escape(text.chars));
      writeln(e);
      writefln("Error: test on line %s", testLine);
      assert(0);
    }
  }

  testParseFields("");
  testParseFields(" ");
  testParseFields("\n");

  testParseFields("// comment");
  testParseFields("# comment");
  testParseFields("/* comment */");
  testParseFields("/* comment\n next-line \n hey */");
  testParseFields("/* comment\n next-line *\n * ** *** \n hey **/");

  testParseFields("first", [FieldToken("first")]);

  //testParseFields("[", [FieldToken("first")]);

}