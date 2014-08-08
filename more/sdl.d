module more.sdl;

import std.array;
import std.string;

import core.vararg;
import std.c.string: memmove;

import more.common;
import more.utf8;


version(unittest) {
  import std.stdio;
}


class SdlParseException : Exception
{
  uint line;
  this(string msg) {
    super(msg);
    line = 0;
  }
  this(uint line, string msg) {
    super(msg);
    this.line = line;
  }
}

struct Attribute {
  const(char)[] id;
  const(char)[] value;
}


struct Tag {
  size_t depth = 1; // 0 means EOF
  uint line    = 1;
  const(char)[] namespace;
  const(char)[] name;
  auto values     = appender!(const(char)[][])();
  auto attributes = appender!(Attribute[])();
  
  version(unittest)
  {
    this(const(char)[] name, const(char)[][] values...) {
      auto colonIndex = name.indexOf(':');
      if(colonIndex > -1) {
	this.namespace = name[0..colonIndex];
	this.name = name[colonIndex+1..$];
      } else {
	this.namespace.length = 0;
	this.name = name;
      }
      foreach(value; values) {
	this.values.put(value);
      }
    }
  }

  void reset() {
    depth = 1;
    line = 1;
    namespace.length = 0;
    name = null;
    values.clear();
    attributes.clear();
  }
  void resetForNextTag()
  {
    this.name = null;
    this.values.clear();
    this.attributes.clear();
  }

  @property
  bool eof() {
    return depth == 0;
  }
  void atEof() {
    if(depth > 1) throw new SdlParseException(format("reached end of sdl but missing the ending '}' on %s tag(s)", depth - 1));
    depth = 0;
  }
  void setNamespace(inout(char)* start, inout(char)* limit)
  {
    this.namespace = (cast(const(char)*)start)[0..limit-start];
  }
  void setName(inout(char)* start, inout(char)* limit)
  {
    this.name = (start == limit) ? "content" : (cast(const(char)*)start)[0..limit-start];
  }
}


bool isIDStart(dchar c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
bool isID(dchar c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '$';
}

enum tooManyEndingBraces = "too many ending braces '}'";
enum noEndingQuote = "string missing ending quote";

// throws SdlParseException or Utf8Exception
void parseSdl(ref Tag tag, ref inout(char)* next, inout(char)* limit)
{
  // developer note:
  //   whenever reading the next character, the next pointer must be saved to cpos
  //   if the character could be used later, but if the next is guaranteed to
  //   be thrown away (such as when skipping till the next newline after a comment)
  //   then cpos does not need to be saved.

  tag.resetForNextTag(); // make sure this is done first

  inout(char)* cpos;
  dchar c;
  inout(char)[] literal;

  void readNext()
  {
    cpos = next;
    c = decodeUtf8(next, limit);
  }
  // skip c and start reading immediately
  void toNextLine()
  {
    while(true) {
      if(next >= limit) { tag.atEof(); return; }
      c = decodeUtf8(next, limit); // no need to save cpos since c will be thrown away
      if(c == '\n') { tag.line++; return; }
    }
  }
  void parseID()
  {
    while(true) {
      if(next >= limit) { tag.atEof(); return; }
      cpos = next;
      c = decodeUtf8(next, limit);
      if(!isID(c)) return;
    }
  }

  // returns true if newline found
  bool skipWhitespaceAndComments(bool stopAtNewline)
  {
    uint lineBefore = tag.line;
    
    while(true) {

      if(c == ' ' || c == '\t') {

	// do nothing (check first as this is the most likely case)

      } else if(c == '\n') {

	tag.line++;
	if(stopAtNewline) return true;

      } else if(c == '#') {

	toNextLine();
	//writefln("[DEBUG] Found '#' comment");

      } else if(c == '-' || c == '/') {

	if(next >= limit) {
	  next = cpos; // rewind
	  return tag.line > lineBefore;
	}

	dchar secondChar = decodeUtf8(next, limit);

	if(secondChar == c) { // '--' or '//'

	  toNextLine();
	  //writefln("[DEBUG] Found '%s%s' comment", secondChar, secondChar);
	
	} else if(secondChar == '*') {

	  throw new Exception("multiline comment not implemented");

	} else {

	  next = cpos; // rewind
	  return tag.line > lineBefore;

	}

      } else {
	
	return tag.line > lineBefore;

      }


      //
      // Goto next character
      //
      if(next >= limit) { tag.atEof(); return tag.line > lineBefore;}
      cpos = next;
      c = decodeUtf8(next, limit);

    }
  }


  // expects c/cpos to point at the first character of the potential literal
  // if it does not match a literal, it will set the literal variable length to 0
  // if it does fina a literal, it will set c/cpos to the next character after the literal
  // and set the the literal string to the literal variable
  void tryParseLiteral() {
    if(c == '"') {

      cpos++;
      bool containsEscapes = false;
      while(true) {
	
	if(next >= limit) throw new SdlParseException(tag.line, noEndingQuote);
	c = decodeUtf8(next, limit); // no need to save cpos since c will be thrown away
	if(c == '"') break;
	if(c == '\\') {
	  containsEscapes = true;
	  if(next >= limit) throw new SdlParseException(tag.line, noEndingQuote);
	  c = decodeUtf8(next, limit);
	} else if(c == '\n') {
	  throw new SdlParseException(tag.line, noEndingQuote);
	}
	  
      }
      
      if(containsEscapes) {
	/* do something differnt if immuable */
	implement("escaped strings");

      } else {
	literal = cpos[0..next - cpos - 1];
      }

      if(next >= limit) {tag.atEof(); return;}
      readNext();
    } else if(c == '`') {

      implement("tick strings");
     
    } else if(c >= '0' && c <= '9' || c == '-') {

      implement("sdl numbers");

    } else if(c == 'n') {

      if(next >= limit) { next = cpos; return; }
      c = decodeUtf8(next, limit);
      if(c != 'u' || next >= limit) { next = cpos; return; }
      c = decodeUtf8(next, limit);
      if(c != 'l' || next >= limit) { next = cpos; return; }
      c = decodeUtf8(next, limit);
      if(c != 'l'                 ) { next = cpos; return; }

      literal = cpos[0..4];

      if(next >= limit) {tag.atEof(); return; }
      readNext();
      
    } else {
      literal.length = 0;
    }
  }


  
  //
  // Read the first character
  //
  if(next >= limit) { tag.atEof(); return; }
  cpos = next;
  c = decodeUtf8(next, limit);

  while(true) {

    skipWhitespaceAndComments(false);
    if(tag.eof) return;

    //
    //
    // Get the tag name/namespace
    //
    //
    if(isIDStart(c)) {

      auto startOfTag = cpos;

      parseID();
      if(tag.eof) {
	tag.namespace.length = 0;
	tag.setName(startOfTag, limit);
	return;
      }

      if(c != ':') {

	tag.namespace.length = 0;
	tag.setName(startOfTag, cpos);

      } else {

	tag.setNamespace(startOfTag, cpos);

	if(next >= limit) {
	  tag.name = "content"; return;
	}
	startOfTag = next;
	c = decodeUtf8(next, limit);
	if(!isIDStart(c)) throw new SdlParseException(
          tag.line, format("expected alphanum or '_' after colon ':' but got '%s'", c));

	parseID();
	tag.setName(startOfTag, next);
	if(tag.eof) return;

      }

      if(skipWhitespaceAndComments(true) || tag.eof) return;
      
    } else if(c == '}') {

      if(tag.depth == 1) throw new SdlParseException(tag.line, tooManyEndingBraces);
      tag.depth--;

      // Read the next character
      if(next >= limit) { tag.atEof(); return; }
      cpos = next;
      c = decodeUtf8(next, limit);

      continue;

    } else if(c == '\\') {

      throw new SdlParseException("Expected tag or '}' but got backslash '\\'");

    } else {

      tag.namespace.length = 0;
      tag.name = "content";

    }


    //
    //
    // Get Values and Attributes
    //
    //
    while(true) {
      //
      // At this point c must contain a non-whitespace character
      // and we must have already parsed the tag name
      //

      if(c == ';') return; // Reached the end of the tag

      //
      // Handle the '\' character to escape newlines
      //
      if(c == '\\') {
	if(next >= limit) return; // (check to make sure ending an sdl file with a backslash is ok)
	c = decodeUtf8(next, limit);

	auto foundNewline = skipWhitespaceAndComments(true);
	if(tag.eof) return;
	if(!foundNewline) throw new SdlParseException("only comments/whitespace can follow a backslash '\\'");

	if(skipWhitespaceAndComments(false)) return; // reached end of the tag
	if(tag.eof) return;

	continue;
      }

      if(c == '{') {
	tag.depth++;
	return;
      }

      if(c == '}') {
	if(tag.depth == 1) throw new SdlParseException(tag.line, tooManyEndingBraces);
	tag.depth--;
	return;
      }


      tryParseLiteral();
      if(literal.length) {

	tag.values.put(literal);
	
      } else {

	

	writefln("[DEBUG] next='%s'", cast(string)next[0..limit-next]);
	implement();

      }

      if(skipWhitespaceAndComments(false) || tag.eof) return;

    }

  }


 RETURN:

}

unittest
{
  Tag parsedTag;

  void testParseSdl(string s, ...)
  {
    auto escapedS = escape(s);
    writefln("[TEST] testing sdl '%s'", escapedS);

    immutable(char) *next = s.ptr;
    immutable(char) *limit = s.ptr + s.length;

    parsedTag.reset();
    parseSdl(parsedTag, next, limit);

    for(auto i = 0; i < _arguments.length; i++) {
      auto expectedTag = va_arg!Tag(_argptr);
      if(parsedTag.namespace != expectedTag.namespace) {
	writefln("Error: expected tag namespace '%s' but got '%s'", expectedTag.namespace, parsedTag.namespace);
	assert(0);
      }
      if(parsedTag.name != expectedTag.name) {
	writefln("Error: expected tag name '%s' but got '%s'", expectedTag.name, parsedTag.name);
	assert(0);
      }
      //writefln("[DEBUG] expected value '%s', actual values '%s'", expectedTag.values.data, parsedTag.values.data);
      if(parsedTag.values.data != expectedTag.values.data) {
	writefln("Error: expected tag values '%s' but got '%s'", expectedTag.values.data, parsedTag.values.data);
	assert(0);
      }
      parseSdl(parsedTag, next, limit);
    }

    if(!parsedTag.eof) {
      writefln("Expected %s tag(s) but got at least one more (depth=%s, name='%s')",
	       _arguments.length, parsedTag.depth, parsedTag.name);
      assert(0);
    }
  }

  void testInvalidSdl(string invalid) {
    auto escapedInvalid = escape(invalid);
    writefln("[TEST] testing invalid sdl '%s'", escapedInvalid);
      
    auto next = invalid.ptr;
    auto limit = invalid.ptr + invalid.length;

    parsedTag.reset();
    try {
      while(true) {
	parseSdl(parsedTag, next, limit);
	if(parsedTag.eof) {
	  writefln("Error: invalid sdl was successfully parsed");
	  assert(0);
	}
      }
    } catch(SdlParseException e) {
    } catch(Utf8Exception e) {
    }
  }

  testParseSdl("");
  testParseSdl("   ");

  testParseSdl("#Comment");
  testParseSdl("#Comment copyright \u00a8");
  testParseSdl("#Comment\n");
  testParseSdl("#Comment\r\n");
  testParseSdl("  #   Comment\r\n");

  testParseSdl("  --   Comment\n");
  testParseSdl(" ------   Comment\n");

  testParseSdl("  #   Comment1 \r\n  -- Comment 2");


  testParseSdl(" //   Comment\n");
  testParseSdl(" ////   Comment\n");

  //testParseSdl("/* a multiline comment \n\r\n\n\n\t hello stuff # -- // */");

  testParseSdl("a", Tag("a"));
  testParseSdl("ab", Tag("ab"));
  testParseSdl("abc", Tag("abc"));
  testParseSdl("firsttag", Tag("firsttag"));
  testParseSdl("funky._-$tag", Tag("funky._-$tag"));

  testParseSdl("a:", Tag("a:content"));
  testParseSdl("ab:", Tag("ab:content"));

  testParseSdl("a:a", Tag("a:a"));
  testParseSdl("ab:a", Tag("ab:a"));

  testParseSdl("a:ab", Tag("a:ab"));
  testParseSdl("ab:ab", Tag("ab:ab"));

  testParseSdl("html:table", Tag("html:table"));
  testParseSdl("html:table", Tag("html:table"));

  testParseSdl(";", Tag("content"));
  testParseSdl("myid;", Tag("myid"));
  testParseSdl("myid;   ", Tag("myid"));
  testParseSdl("myid #comment", Tag("myid"));
  testParseSdl("myid # comment \n", Tag("myid"));
  testParseSdl("myid -- comment \n # more comments\n", Tag("myid"));


  testParseSdl("tag1\ntag2", Tag("tag1"), Tag("tag2"));
  testParseSdl("tag1;tag2\ntag3", Tag("tag1"), Tag("tag2"), Tag("tag3"));

  testInvalidSdl("myid {");
  testInvalidSdl("myid {\n\n");

  testParseSdl("tag1{}", Tag("tag1"));
  testParseSdl("tag1{}tag2", Tag("tag1"), Tag("tag2"));
  testParseSdl("tag1{}\ntag2", Tag("tag1"), Tag("tag2"));

  testParseSdl("tag1{tag1.1}tag2", Tag("tag1"), Tag("tag1.1"), Tag("tag2"));

  //
  // Handling the backslash '\' character
  //
  testInvalidSdl(`\`); // slash must in the context of a tag
  testInvalidSdl(`\`);
  testInvalidSdl(`tag \ x`);

  testParseSdl("tag\\", Tag("tag")); // Make sure this is valid sdl
  testParseSdl("tag \\  \n \\ \n \"hello\"", Tag("tag", `"hello"`));
  
  //
  // The null literal
  //
  //testInvalidSdl("tag n");
  //testInvalidSdl("tag nu");
  //testInvalidSdl("tag nul");

  testParseSdl("tag null", Tag("tag", "null"));

  //testParseSdl("tag n=\"value\"", Tag("tag", "n=\"value\""));
  //testParseSdl("tag nu=\"value\"", Tag("tag", "nu=\"value\""));
  //testParseSdl("tag nul=\"value\"", Tag("tag", "nul=\"value\""));



  //
  // String Literals
  //
  testParseSdl(`a "apple"`, Tag("a", `"apple"`));
  testParseSdl("a \"pear\"\n", Tag("a", `"pear"`));
  testParseSdl("a \"cat\"\"dog\"\"bear\"\n", Tag("a", `"cat"`, `"dog"`, `"bear"`));
  testParseSdl("a \"tree\";b \"truck\"\n", Tag("a", `"tree"`), Tag("b", `"truck"`));

  

}


unittest
{
}