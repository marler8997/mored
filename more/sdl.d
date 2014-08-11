//
// TODO: write a comprehensive unit test suite
//       implement a string generator iterator like this
//
//
//       Note: if '|' and '{' '}' are at the same depth, the curly braces
//             are expanded first, and then the '| is evaluated so the following:
//       "1|2{3|4}"
//       "1"
//       "23"
//       "24"

//       
//       "t{able|r{ee|ay}}
//       table
//       tree
//       ...

//       "app
//       "app{le|store}
//

// TODO: change enforceValues to check for null and throw duplicate error
// TODO: implement multiline comments
// TODO: true/false literals
// TODO: handle utf-8 BOM
// TODO: write a generic input sdl parser that uses parseSdlTag
//
module more.sdl;

import std.array;
import std.string;
import std.range;
import std.conv;
import std.bitmanip;

import std.c.string: memmove;

import more.common;
import more.utf8;

version(unittest) {
  import std.stdio;

  char[2048] sdlBuffer;
  char[] setupSdlText(string sdlText, bool copySdl) {
    if(!copySdl) return cast(char[])sdlText;

    if(sdlText.length >= sdlBuffer.length) throw new Exception(format("attempting to copy sdl of length %s but sdlBuffer is only of length %s", sdlText.length, sdlBuffer.length));
    sdlBuffer[0..sdlText.length] = sdlText;
    return sdlBuffer[0..sdlText.length];
  }
/+
  char* setupSdlText(string sdlText, bool copySdl) {
    if(!copySdl) return cast(char*)sdlText.ptr;

    if(sdlText.length >= sdlBuffer.length) throw new Exception(format("attempting to copy sdl of length %s but sdlBuffer is only of length %s", sdlText.length, sdlBuffer.length));
    sdlBuffer[0..sdlText.length] = sdlText;
    return sdlBuffer.ptr;
  }
+/
}

enum SdlErrorType {
  unknown,
  braceAfterNewline,
  mixedValuesAndAttributes,
}
class SdlParseException : Exception
{
  SdlErrorType type;
  uint line;
  this(uint line, string msg) {
    this(SdlErrorType.unknown, line, msg);
  }
  this(SdlErrorType errorType, uint line, string msg) {
    super((line == 0) ? msg : "line "~to!string(line)~": "~msg);
    this.type = errorType;
    this.line = line;
  }
}




struct Attribute {
  const(char)[] namespace;
  const(char)[] id;
  const(char)[] value;
}

struct Tag {
  // These bitfields set flags to support non-standard
  // sdl.  The default value 0 will disable all flags
  // so the parser only allows standard sdl;
  mixin(bitfields!(bool,  "allowMixedValuesAndAttributes", 1,
		   bool,  "allowBraceAfterNewline", 1,
		   bool,  "preserveSdlText", 1,
		   ubyte, "", 5));
  void resetOptions() {
    this.allowMixedValuesAndAttributes = false;
    this.allowBraceAfterNewline = false;
    this.preserveSdlText = false;
  }


  size_t depth = 0;
  uint line    = 1;
  const(char)[] namespace;
  const(char)[] name;
  auto values     = appender!(const(char)[][])();
  auto attributes = appender!(Attribute[])();

  private bool hasChildren;



  
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

	const(char)[] attributeNamespace = "";
	size_t equalIndex = size_t.max;

	// check if it is an attribute
	if(value.length && isIDStart(value[0])) {
	  size_t i = 1;
	  while(true) {
	    if(i >= value.length) break;
	    auto c = value[i];
	    if(!isID(value[i])) {
	      if(c == ':') {
		if(attributeNamespace.length) throw new Exception("contained 2 colons?");
		attributeNamespace = value[0..i];
		i++;
		continue;
	      }
	      if(value[i] == '=') {
		equalIndex = i;
	      }
	      break;
	    }
	    i++;
	  }
	}

	if(equalIndex == size_t.max) {
	  this.values.put(value);
	} else {
	  Attribute a = {attributeNamespace, value[attributeNamespace.length..equalIndex], value[equalIndex+1..$]};
	  this.attributes.put(a);
	}

      }
    }
  }

  void reset() {
    depth = 0;
    line = 1;
    namespace.length = 0;
    name = null;
    values.clear();
    attributes.clear();
  }


  bool parse(char[]* str) {
    /+
    char* start = str.ptr;
    char* limit = start + str.length;
    bool done = parseSdlTag(&this, start, limit);
    str = start[0..limit-start];
    return done;
    +/
    return parseSdlTag(&this, str);
  }


  void resetForNextTag()
  {
    this.name = null;
    if(hasChildren) {
      hasChildren = false;
      this.depth++;
    }
    this.values.clear();
    this.attributes.clear();
  }

  void setNamespace(inout(char)* start, inout(char)* limit)
  {
    this.namespace = (cast(const(char)*)start)[0..limit-start];
  }
  void setName(inout(char)* start, inout(char)* limit)
  {
    this.name = (start == limit) ? "content" : (cast(const(char)*)start)[0..limit-start];
  }

  void toSdl(S, string indent = "    ")(S sink) if(isOutputRange!(S,const(char)[])) {
    for(auto i = 0; i < depth; i++) {
      sink.put(indent);
    }
    if(namespace.length) {
      sink.put(namespace);
      sink.put(":");
    }
    sink.put(name);
    foreach(value; values.data) {
      sink.put(" ");
      sink.put(value);
    }
    foreach(attribute; attributes.data) {
      sink.put(" ");
      if(attribute.namespace.length) {
	sink.put(attribute.namespace);
	sink.put(":");
      }
      sink.put(attribute.id);
      sink.put("=");
      sink.put(attribute.value);
    }
    if(hasChildren) {
      sink.put(" {\n");
    } else {
      sink.put("\n");
    }
  }


  //
  // User Methods
  //
  void throwIsUnknown() {
    throw new SdlParseException(line, format("unknown tag '%s'", name));
  }
  void throwIsDuplicate() {
    throw new SdlParseException(line, format("tag '%s' appeared more than once", name));
  }
/+
  const(char)[] enforceOneValue() {
    if(values.data.length == 1) return values.data[0];
    throw new SdlParseException(line, format("tag '%s' must have exactly 1 value but had %s", name, values.data.length));
  }
+/
  void enforceOneValue(T)(ref T t) {
    if(values.data.length != 1)
      throw new SdlParseException(line, format("tag '%s' must have exactly 1 value but had %s", name, values.data.length));
    const(char)[] literal = values.data[0];
    static if( isSomeString!T ) {
      if(literal[0] != '"') throw new SdlParseException(line, format("tag '%s' must have exactly one string literal but had another literal type", name));
      t = literal[1..$-1]; // remove surrounding quotes
    } else {
      assert(0, format("Cannot convert sdl literal to D '%s' type", typeid(T)));
    }
  }
/+
  const(char)[][] enforceValues() {
    if(values.data.length == 0) throw new SdlParseException(line, format("tag '%s' must have at least 1 value", name));
    //writefln("[DEBUG] values.data.length = %s", values.data.length);
    const(char)[][] newValues = new const(char)[][values.data.length];
    newValues[] = values.data;
    return newValues;
  }
+/

  void enforceValues(T, bool append=false)(ref T[] t) {
    if(values.data.length == 0) throw new SdlParseException(line, format("tag '%s' must have at least 1 value", name));
    t = new T[values.data.length];
    foreach(i, literal; values.data) {
      static if( isSomeString!T ) {
	if(literal[0] != '"') throw new SdlParseException(line, format("tag '%s' must have exactly one string literal but had another literal type", name));
	t[i] = literal[1..$-1]; // remove surrounding quotes
      } else {
	assert(0, format("Cannot convert sdl literal to D '%s' type", typeid(T)));
      }
    }
  }

  void enforceNoAttributes() {
    if(attributes.data.length) throw new SdlParseException(line, format("tag '%s' cannot have any attributes", name));
  }
  void enforceNoChildren() {
    if(hasChildren) throw new SdlParseException(line, format("tag '%s' cannot have any children", name));
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
enum invalidBraceFmt = "found '{' on a different line than it's tag '%s'.  fix the sdl by moving '{' to the same line";
enum mixedValuesAndAttributesFmt = "SDL values cannot appear after attributes, bring '%s' in front of the attributes for tag '%s'";



struct SdlParser(A)
{
  char[] buffer;
  A allocator;
  char[] leftover;
  this(char[] buffer, A allocator)
  {
    this.buffer = buffer;
    this.allocator = allocator;
  }
  ref Sink parse(Source,Sink)(Source source, Sink sink)
    if (isInputRange!Source &&
        isOutputRange!(Sink, ElementType!Source))
  {
    // todo implement
  }
}


/// Iterates over the given SDL string pointed to by next, saving slices for every
/// tag/value/attribute.  This function assumes that the given SDL string contains
/// at least one full tag. This function does not allocate any memory so after the
/// tag is populated it is up to the caller to copy any memory they wish to save,
/// or they can keep the original sdl text in memory to preserve the slices of the tag.
/// returns true if it found a tag
/// throws SdlParseException or Utf8Exception
bool parseSdlTag(Tag* tag, char[]* sdlText)
//bool parseSdlTag(Tag* tag, ref char* next, const char* limit)
{
  // developer note:
  //   whenever reading the next character, the next pointer must be saved to cpos
  //   if the character could be used later, but if the next is guaranteed to
  //   be thrown away (such as when skipping till the next newline after a comment)
  //   then cpos does not need to be saved.
  char *next = (*sdlText).ptr;
  char *limit = next + sdlText.length;


  tag.resetForNextTag(); // make sure this is done first

  char* cpos;
  dchar c;
  char[] attributeNamespace;
  char[] attributeID;
  char[] literal;

  void enforceNoMoreTags() {
    if(tag.depth > 0) throw new SdlParseException(tag.line, format("reached end of sdl but missing the ending '}' on %s tag(s)", tag.depth));
  }

  void readNext()
  {
    cpos = next;
    c = decodeUtf8(next, limit);
  }

  // expected c/cpos to b pointing at a character before newline, so will ready first
  // before checking for newlines
  void toNextLine()
  {
    while(true) {
      if(next >= limit) { return; }
      c = decodeUtf8(next, limit); // no need to save cpos since c will be thrown away
      if(c == '\n') { tag.line++; return; }
    }
  }

  // expects c/cpos to point at the first character of the id and for it to already be checked
  // when this function is done, c/cpos will pointing to the first character after the id, or
  // cpos == limit if there are no characters after the id
  void parseID()
  {
    while(true) {
      if(next >= limit) { cpos = cast(char*)limit; return; }
      readNext();
      if(!isID(c)) return;
    }
  }


  // expects c/cpos to point at the first character after the id
  // returns true if the id is actually a value
  // NOTE: this should only becaused if no namespace was found yet, this function
  //       will always return false if c/cpos is pointing to a ':' which indicates
  //       that it is a namespace even if the namespace could be a value like null or true/false
  bool currentIDIsValue(char* startOfID) {
    //switch on the length
    switch(cpos - startOfID) {
    case 0-1: return false;
    case 2: return startOfID[0..2] == "on";
    case 3: return startOfID[0..3] == "off";
    case 4: return startOfID[0..4] == "null" ||
	           startOfID[0..4] == "true";
    case 5: return startOfID[0..5] == "false";
    default: return false;
    }
  }
  
  // returns true if a newline was found
  // expects c/cpos to point at the first character of the potential whitespace/comment
  // after this function returns, the next pointer will point at the first character
  // after the whitespace comments
  // c/cpos should be ignored after this function is called and readNext should be called to set them
  // NOTE: the reason this function doesn't set c/cpos to the next character is so that the caller
  //       can rewind the next pointer if they need to by executing next = cpos;  This may need to be
  //       done if for example a close brace '}' is read and needs to be unread for the next call
  bool skipWhitespaceAndComments()
  {
    uint lineBefore = tag.line;
    
    while(true) {

      if(c == ' ' || c == '\t') {

	// do nothing (check first as this is the most likely case)

      } else if(c == '\n') {

	tag.line++;

      } else if(c == '#') {

	toNextLine();

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
	
	next = cpos; // rewind
	return tag.line > lineBefore;

      }

      //
      // Goto next character
      //
      if(next >= limit) { return tag.line > lineBefore;}
      readNext();
    }
  }


  // expects c/cpos to point at the first character of the potential literal
  // if it does not match a literal, it will set the literal variable length to 0
  // if it does find a literal, it will set c/cpos to the next character after the literal
  // and set the the literal string to the literal variable
  void tryParseLiteral() {
    literal.length = 0; // clear any previous literal

    if(c == '"') {

      bool containsEscapes = false;

      while(true) {
	
	if(next >= limit) throw new SdlParseException(tag.line, noEndingQuote);
	c = decodeUtf8(next, limit); // no need to save cpos since c will be thrown away
	if(c == '"') break;
	if(c == '\\') {
	  containsEscapes = true;
	  if(next >= limit) throw new SdlParseException(tag.line, noEndingQuote);
	  // NOTE TODO: remember to handle escaped newlines
	  c = decodeUtf8(next, limit);
	} else if(c == '\n') {
	  throw new SdlParseException(tag.line, noEndingQuote);
	}
	  
      }
      
      if(containsEscapes) {
	/* do something differnt if immuable */
	implement("escaped strings");

      } else {
	literal = cpos[0..next - cpos];
      }

      cpos = next;
      if( next < limit) c = decodeUtf8(next, limit);

    } else if(c == '`') {

      implement("tick strings");
     
    } else if(c >= '0' && c <= '9' || c == '-') {

      implement("sdl numbers");

    } else if(c == 'n') {

      writefln("[DEBUG] checking if value is null '%s' (limit-next=%s)", cpos[0..4], limit-next);

      // NOTE: I need to make sure that I can treat the keyword literals
      //       as ascii.  This wil not work if the characters are encoded
      //       using UTF-8 multibyte characters when they don't need to be.
      if(limit >= next + 3) {
	if(cpos[0..4] == "null") {
	  literal = cpos[0..4]; // I could set it to the "null" string instead, not sure 
	  cpos += 4;
	  next = cpos;
	  c = decodeUtf8(next, limit);
	}
      }

    } else {
      literal.length = 0;
    }
  }


  
  //
  // Read the first character
  //
  if(next >= limit) { enforceNoMoreTags(); goto RETURN_NO_TAG; }
  readNext();

  while(true) {

    skipWhitespaceAndComments();
    if(next >= limit) { enforceNoMoreTags(); goto RETURN_NO_TAG; }
    readNext(); // should be called after skipping whitespace and comments

    //
    //
    // Get the tag name/namespace
    //
    // todo: handle lines that start with literals
    //
    if(isIDStart(c)) {

      auto startOfTag = cpos;

      parseID();

      if((cpos >= limit || c != ':') && currentIDIsValue(startOfTag)) {
	tag.namespace.length = 0;
	tag.name = "content";
	tag.values.put(startOfTag[0..cpos-startOfTag]);
      } else {

	if(cpos >= limit) {
	  tag.namespace.length = 0;
	  tag.setName(startOfTag, limit);
	  goto RETURN_TAG;
	}

	if(c != ':') {

	  tag.namespace.length = 0;
	  tag.setName(startOfTag, cpos);

	} else {

	  tag.setNamespace(startOfTag, cpos);

	  if(next >= limit) {
	    tag.name = "content";
	    goto RETURN_TAG;
	  }
	  startOfTag = next;
	  c = decodeUtf8(next, limit);
	  if(!isIDStart(c)) throw new SdlParseException(
	    tag.line, format("expected alphanum or '_' after colon ':' but got '%s'", c));

	  parseID();
	  tag.setName(startOfTag, cpos);
	  if(cpos >= limit) goto RETURN_TAG;

	}
      }

    } else if(c == '}') {

      if(tag.depth == 0) throw new SdlParseException(tag.line, tooManyEndingBraces);
      tag.depth--;

      // Read the next character
      if(next >= limit) { enforceNoMoreTags(); goto RETURN_NO_TAG; }
      cpos = next;
      c = decodeUtf8(next, limit);

      continue;

    } else if(c == '\\') {
      throw new SdlParseException(tag.line, "expected tag or '}' but got backslash '\\'");
    } else if(c == '{') {
      throw new SdlParseException(tag.line, "expected tag or '}' but got '{'");
    } else {

      tag.namespace.length = 0;
      tag.name = "content";

    }

    //
    //
    // Found a valid tag, now get values and attributes
    //
    //
  GET_VALUES_AND_ATTRIBUTES:
    while(true) {

      // At the beginning of this loop, it is expected that c/cpos will be pointing the
      // next character after the last thing (tag/value/attribute)
      
      
      if(cpos >= limit) goto RETURN_TAG; // I may not need this check
      auto foundNewline = skipWhitespaceAndComments();
      if(next >= limit) goto RETURN_TAG;
      if(foundNewline) {
	// check if it is a curly brace to either print a useful error message
	// or determine if the tag has children
	readNext();
	if(c != '{') {
	  next = cpos; // rewind so whatever character it is will
	               // be parsed again on the next call
	  goto RETURN_TAG;
	}
	if(tag.allowBraceAfterNewline) {
	  tag.hasChildren = true;
	  goto RETURN_TAG;
	}

	throw new SdlParseException(SdlErrorType.braceAfterNewline, tag.line,
				    format(invalidBraceFmt, tag.name));
      }
      readNext();


      //
      // At this point c must contain a non-whitespace character
      // and we must have already parsed the tag name
      //

      if(c == ';') goto RETURN_TAG;

      //
      // Handle the '\' character to escape newlines
      //
      if(c == '\\') {
	if(next >= limit) goto RETURN_TAG; // (check to make sure ending an sdl file with a backslash is ok)
	c = decodeUtf8(next, limit);

	foundNewline = skipWhitespaceAndComments();
	if(next >= limit) goto RETURN_TAG;
	if(!foundNewline) throw new SdlParseException(tag.line, "only comments/whitespace can follow a backslash '\\'");
	readNext(); // should be called after skiping whitespace and comments

	continue;
      }

      if(c == '{') {
	tag.hasChildren = true; // depth will be incremented at the next parse
	goto RETURN_TAG;
      }

      if(c == '}') {
	if(tag.depth == 0) throw new SdlParseException(tag.line, tooManyEndingBraces);
	next = cpos; // rewind so the '}' will be seen on the next call and
	             // the depth will change on the next call                     
	goto RETURN_TAG;
      }

      //
      // Try to parse an attribute
      //
      if(isIDStart(c)) {

	auto startOfID = cpos;
	parseID();

	// check if the id is actually a value
	if(cpos >= limit || (c != ':' && c != '=')) {

	  if(currentIDIsValue(startOfID)) {
	    tag.values.put(startOfID[0..cpos-startOfID]);
	    continue GET_VALUES_AND_ATTRIBUTES;
	  }

	}

	if(cpos >= limit) {
	  throw new SdlParseException(tag.line, format("expected value or attribute but found an id '%s'", cast(char[])startOfID[0..next-startOfID]));
	}

	if(c == ':') {
	  attributeNamespace = startOfID[0..cpos-startOfID];

	  if(next >= limit) throw new SdlParseException(tag.line, "sdl cannot end with a ':' character");
	  startOfID = cpos;
	  c = decodeUtf8(next, limit);
	  if(!isIDStart(c)) throw new SdlParseException(tag.line, "an sdl id must follow the colon ':' character");
			      
	  parseID();
	  if(cpos >= limit) throw new SdlParseException(tag.line, "expected '=' to follow attribute name but got EOF");
	  attributeID = startOfID[0..cpos-startOfID];
	} else {
	  attributeID = startOfID[0..cpos-startOfID];
	}

	if(c != '=') throw new SdlParseException(tag.line, format("expected '=' to follow attribute name but got '%s'", c));
	readNext();
      } else {

	attributeNamespace.length = 0;
	attributeID.length = 0;

      }

      tryParseLiteral();
      if(literal.length) {

	if(attributeID.length > 0) {
	  Attribute attribute = {attributeNamespace, attributeID, literal};
	  tag.attributes.put(attribute);
	} else {

	  if(tag.attributes.data.length) {
	    if(!tag.allowMixedValuesAndAttributes)
	      throw new SdlParseException(SdlErrorType.mixedValuesAndAttributes, tag.line,
					  format(mixedValuesAndAttributesFmt, literal, tag.name));
	  }

	  tag.values.put(literal);
	}

	if(cpos >= limit) goto RETURN_TAG;
	
      } else {

	if(attributeID.length > 0) throw new SdlParseException(tag.line, "expected sdl literal to follow attribute '=' but was not a literal");

	if(c == '\0') throw new Exception("possible code bug: found null");
	throw new Exception(format("Unhandled character '%s' (code=0x%x)", c, cast(uint)c));
	implement();

      }
    }

  }

  assert(0);

 RETURN_TAG:
  *sdlText = next[0..limit-next];
  return true;

 RETURN_NO_TAG:
  (*sdlText) = limit[0..0];
  return false;
}





unittest
{
  mixin(scopedTest!"SdlParse");

  Tag parsedTag;


  struct SdlTest
  {
    bool copySdl;
    string sdlText;
    Tag[] expectedTags;
    this(bool copySdl, string sdlText, Tag[] expectedTags...) {
      this.copySdl = copySdl;
      this.sdlText = sdlText;
      this.expectedTags = expectedTags;
    }
  }

  void testParseSdl(bool copySdl, string sdlText, Tag[] expectedTags...)
  {
    auto escapedSdlText = escape(sdlText);
    writefln("[TEST] testing sdl '%s'", escapedSdlText);

    char[] next = setupSdlText(sdlText, copySdl);
    //char* limit = next + sdlText.length;

    parsedTag.reset();

    for(auto i = 0; i < expectedTags.length; i++) {
      if(!parseSdlTag(&parsedTag, &next)) {
	writefln("Expected %s tag(s) but only got %s", expectedTags.length, i);
	assert(0);
      }

      auto expectedTag = expectedTags[i];
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
      if(parsedTag.attributes.data != expectedTag.attributes.data) {
	writefln("Error: expected tag attributes '%s' but got '%s'", expectedTag.attributes.data, parsedTag.attributes.data);
	assert(0);
      }
    }

    if(parseSdlTag(&parsedTag, &next)) {
      writefln("Expected %s tag(s) but got at least one more (depth=%s, name='%s')",
	       expectedTags.length, parsedTag.depth, parsedTag.name);
      assert(0);
    }
  }

  void testInvalidSdl(bool copySdl, string sdlText, SdlErrorType expectedErrorType = SdlErrorType.unknown) {
    auto escapedSdlText = escape(sdlText);
    writefln("[TEST] testing invalid sdl '%s'", escapedSdlText);

    SdlErrorType actualErrorType = SdlErrorType.unknown;

    char[] next = setupSdlText(sdlText, copySdl);
    //char* next = setupSdlText(sdlText, copySdl);
    //char* limit = next + sdlText.length;
      
    parsedTag.reset();
    try {
      while(parseSdlTag(&parsedTag, &next)) { }
      writefln("Error: invalid sdl was successfully parsed: %s", sdlText);
      assert(0);
    } catch(SdlParseException e) {
      writefln("[TEST]    got expected error on line %s: %s", e.line, e.msg);
      actualErrorType = e.type;
    } catch(Utf8Exception e) {
      writefln("[TEST]    got expected error: %s", e.msg);
    }

    if(expectedErrorType != SdlErrorType.unknown &&
       expectedErrorType != actualErrorType) {
      writefln("expected error '%s' but got error '%s'", expectedErrorType, actualErrorType);
      assert(0);
    }

  }

  testParseSdl(false, "");
  testParseSdl(false, "   ");

  testParseSdl(false, "#Comment");
  testParseSdl(false, "#Comment copyright \u00a8");
  testParseSdl(false, "#Comment\n");
  testParseSdl(false, "#Comment\r\n");
  testParseSdl(false, "  #   Comment\r\n");

  testParseSdl(false, "  --   Comment\n");
  testParseSdl(false, " ------   Comment\n");

  testParseSdl(false, "  #   Comment1 \r\n  -- Comment 2");


  testParseSdl(false, " //   Comment\n");
  testParseSdl(false, " ////   Comment\n");

  //testParseSdl(false, "/* a multiline comment \n\r\n\n\n\t hello stuff # -- // */");

  testParseSdl(false, "a", Tag("a"));
  testParseSdl(false, "ab", Tag("ab"));
  testParseSdl(false, "abc", Tag("abc"));
  testParseSdl(false, "firsttag", Tag("firsttag"));
  testParseSdl(false, "funky._-$tag", Tag("funky._-$tag"));

  testParseSdl(false, "a:", Tag("a:content"));
  testParseSdl(false, "ab:", Tag("ab:content"));

  testParseSdl(false, "a:a", Tag("a:a"));
  testParseSdl(false, "ab:a", Tag("ab:a"));

  testParseSdl(false, "a:ab", Tag("a:ab"));
  testParseSdl(false, "ab:ab", Tag("ab:ab"));

  testParseSdl(false, "html:table", Tag("html:table"));

  testParseSdl(false, ";", Tag("content"));
  testParseSdl(false, "myid;", Tag("myid"));
  testParseSdl(false, "myid;   ", Tag("myid"));
  testParseSdl(false, "myid #comment", Tag("myid"));
  testParseSdl(false, "myid # comment \n", Tag("myid"));
  testParseSdl(false, "myid -- comment \n # more comments\n", Tag("myid"));


  testParseSdl(false, "tag1\ntag2", Tag("tag1"), Tag("tag2"));
  testParseSdl(false, "tag1;tag2\ntag3", Tag("tag1"), Tag("tag2"), Tag("tag3"));

  testInvalidSdl(false, "myid {");
  testInvalidSdl(false, "myid {\n\n");

  testParseSdl(false, "tag1{}", Tag("tag1"));
  testParseSdl(false, "tag1{}tag2", Tag("tag1"), Tag("tag2"));
  testParseSdl(false, "tag1{}\ntag2", Tag("tag1"), Tag("tag2"));

  testParseSdl(false, "tag1{tag1.1}tag2", Tag("tag1"), Tag("tag1.1"), Tag("tag2"));

  //
  // Handling the backslash '\' character
  //
  testInvalidSdl(false, `\`); // slash must in the context of a tag
  testInvalidSdl(false, `\`);
  testInvalidSdl(false, `tag \ x`);

  testParseSdl(false, "tag\\", Tag("tag")); // Make sure this is valid sdl
  testParseSdl(false, "tag \\  \n \\ \n \"hello\"", Tag("tag", `"hello"`));
  
  //
  // The null literal
  //
  testInvalidSdl(false, "tag n");
  testInvalidSdl(false, "tag nu");
  testInvalidSdl(false, "tag nul");

  testParseSdl(false, "tag null", Tag("tag", "null"));

  testParseSdl(false, "tag n=\"value\"", Tag("tag", "n=\"value\""));
  testParseSdl(false, "tag nu=\"value\"", Tag("tag", "nu=\"value\""));
  testParseSdl(false, "tag nul=\"value\"", Tag("tag", "nul=\"value\""));
  testParseSdl(false, "tag null=\"value\"", Tag("tag", "null=\"value\""));

  testParseSdl(false, "tag null=null", Tag("tag", "null=null"));


  //
  // String Literals
  //
  testParseSdl(false, `a "apple"`, Tag("a", `"apple"`));
  testParseSdl(false, "a \"pear\"\n", Tag("a", `"pear"`));
  testParseSdl(false, "a \"left\"\nb \"right\"", Tag("a", `"left"`), Tag("b", `"right"`));
  testParseSdl(false, "a \"cat\"\"dog\"\"bear\"\n", Tag("a", `"cat"`, `"dog"`, `"bear"`));
  testParseSdl(false, "a \"tree\";b \"truck\"\n", Tag("a", `"tree"`), Tag("b", `"truck"`));

  //
  // Attributes
  //
  testParseSdl(false, "tag attr=null", Tag("tag", "attr=null"));
  testParseSdl(false, "tag \"val\" attr=null", Tag("tag", `"val"`, "attr=null"));

  auto mixedValuesAndAttributesTests = [
    SdlTest(false, "tag attr=null \"val\"", Tag("tag", "attr=null", `"val"`)) ];
					
  foreach(test; mixedValuesAndAttributesTests) {
    testInvalidSdl(test.copySdl, test.sdlText, SdlErrorType.mixedValuesAndAttributes);
  }
  writefln("[TEST] setting allowMixedValuesAndAttributes = true;");
  parsedTag.allowMixedValuesAndAttributes = true;
  foreach(test; mixedValuesAndAttributesTests) {
    testParseSdl(test.copySdl, test.sdlText, test.expectedTags);
  }
  writefln("[TEST] resetting options to default");
  parsedTag.resetOptions();


  //
  // Children
  //
  testInvalidSdl(false, "{}"); // no line can start with a curly brace

  auto braceAfterNewlineTests = [
    SdlTest(false, "tag\n{  child\n}", Tag("tag"), Tag("child")),
    SdlTest(false, "colors \"hot\" \n{  yellow\n}", Tag("colors", `"hot"`), Tag("yellow")) ];

  foreach(test; braceAfterNewlineTests) {
    testInvalidSdl(test.copySdl, test.sdlText, SdlErrorType.braceAfterNewline);
  }
  writefln("[TEST] setting allowBraceAfterNewline = true");
  parsedTag.allowBraceAfterNewline = true;
  foreach(test; braceAfterNewlineTests) {
    testParseSdl(test.copySdl, test.sdlText, test.expectedTags);
  }
  writefln("[TEST] resetting options to default");
  parsedTag.resetOptions();


  //
  // Odd corner cases for this implementation
  //
  testParseSdl(false, "tag null;", Tag("tag", "null"));
  testParseSdl(false, "tag null{}", Tag("tag", "null"));
  testParseSdl(false, "tag true;", Tag("tag", "null"));
  testParseSdl(false, "tag true{}", Tag("tag", "null"));
  testParseSdl(false, "tag false;", Tag("tag", "null"));
  testParseSdl(false, "tag false{}", Tag("tag", "null"));


  // TODO: testing using all keywords as namespaces true:id, etc.
  testParseSdl(false, "tag null:null=\"value\";", Tag("tag", "null:null=\"value\""));
  testParseSdl(false, "null", Tag("content", "null"));



  //
  // Full Parses
  //
  testParseSdl(false, `
name "joe"
children {
  name "jim"
}`, Tag("name", `"joe"`), Tag("children"), Tag("name", `"jim"`));

  testParseSdl(false, `
parent name="jim" {
  child "hasToys" name="joey" {
     # just a comment here for now
  }
}`, Tag("parent", "name=\"jim\""), Tag("child", "name=\"joey\"", `"hasToys"`));


  testParseSdl(false,`html:table {
  html:tr {
    html:th "Name"
    html:th "Age"
    html:th "Pet"
  }
  html:tr {
    html:td "Brian"
    html:td 34
    html:td "Puggy"
  }
  tr {
    td "Jackie"
    td 27
    td null
  }
}`, Tag("html:table"),
      Tag("html:tr"),
        Tag("html:th", `"Name"`),
        Tag("html:th", `"Age"`),
        Tag("html:th", `"Pet"`),
      Tag("html:tr"),
        Tag("html:td", `"Brian"`),
        Tag("html:td", `34`),
        Tag("html:td", `"Puggy"`),
      Tag("tr"),
        Tag("td", `"Jackie"`),
        Tag("td", `27`),
        Tag("td", `null`));





  // return false if no more permutations
  bool nextPermutation(ref size_t[] permutation, size_t max) {
    size_t off = permutation.length - 1;
    while(true) {
      if(permutation[off] < max) {
	permutation[off]++;
	return true;
      }
      permutation[off] = 0;
      if(off == 0) return false;
      off--;
    }
  }





  struct Permuter {
    string[] elements;
    size_t[] fullPermutationIndexBuffer;

    private size_t[] currentPermutationBuffer;
    bool isEmpty;

    this(string[] elements, size_t[] fullPermutationIndexBuffer) {
      this.elements = elements;
      this.fullPermutationIndexBuffer = fullPermutationIndexBuffer;

      this.currentPermutationBuffer = fullPermutationIndexBuffer[0..1];
      this.currentPermutationBuffer[] = 0;
    }

    bool empty() { return isEmpty; }
    void putInto(ref WriteBuffer!char buffer) {
      foreach(idx; currentPermutationBuffer) {
	buffer.put(elements[idx]);
      }
    }
    void popFront() {
      bool isNowEmpty = !nextPermutation(this.currentPermutationBuffer, elements.length - 1);
      if(isNowEmpty) {
	if(currentPermutationBuffer.length >= fullPermutationIndexBuffer.length) {
	  this.isEmpty = true;
	} else {
	  currentPermutationBuffer.length++;
	  currentPermutationBuffer[] = 0;
	}
      }
    }
  }


  enum maxPermutationCount = 5;
  

  //
  // Generated tests
  //
  enum preWhitespace = [" ", "\t", "\n"];
  size_t[3] preWhitespacePermutation;


  Permuter preWhitespacePermuter = Permuter(preWhitespace, preWhitespacePermutation);

/+  
  for(; !preWhitespacePermuter.empty; preWhitespacePermuter.popFront()) {
    auto preWhitespaceBuffer = WriteBuffer!char(sdlBuffer);
    preWhitespacePermuter.putInto(preWhitespaceBuffer);
    writefln("preWhitespace-permutation '%s'", escape(preWhitespaceBuffer.slice(sdlBuffer.ptr)));

    
    //auto newWriteBuffer = writeBuffer;
    //tnewWriteBuffer.put("tag");
    ///testParseSdl(newWriteBuffer.slice(sdlBuffer.ptr), 
    

  }
+/
/+
  for(auto permutationLength = 1; permutationLength <= maxPermutationCount; permutationLength++) {
    writefln("permutationLength %s", permutationLength);

    size_t[] permutation = whitespacePermutation[0..permutationLength];
    permutation[] = 0;

    do {
      size_t off = 0;

      foreach(idx; permutation) {
	sdlBuffer[off++] = whitespace[idx];
      }

      writefln("Permutation: '%s'", escape(sdlBuffer[0..permutationLength]));

    } while(nextPermutation(permutation, whitespace.length - 1));
  }
+/



}





struct SdlWalker
{
  Tag* tag;
  char[] sdl;

  bool tagAvailable;
  bool tagAlreadyPopped;

  this(Tag* tag, char[] sdl) {
    this.tag = tag;
    this.sdl = sdl;
    tagAvailable = parseSdlTag(this.tag, &this.sdl);
  }

  @property
  bool empty() { return !tagAvailable; }

  @property
  bool front() { return false; }
  
  void popFront() {
    popFront(0);
  }
  private void popFront(size_t depth, bool skipChildren = false) {
    if(tagAlreadyPopped) {
      if(depth < tag.depth) throw new Exception("possible code bug here?");
      if(tag.depth == depth) {
	tagAlreadyPopped = false;
      }
    } else {
      size_t previousDepth = tag.depth;
      const(char)[] previousName = tag.name;

      tagAvailable = parseSdlTag(this.tag, &sdl);

      if(this.tag.depth > depth && !skipChildren)
	throw new Exception(format("forgot to call children on tag '%s' at depth %s", previousName, previousDepth));
      if(this.tag.depth < depth) {
	tagAlreadyPopped = true;
      }
    }
  }

  public ChildrenWalker children() {
    return ChildrenWalker(&this);
  }

  struct ChildrenWalker {
    SdlWalker* walker;
    const size_t depth;

    this(SdlWalker* walker) {
      if(!walker.tag.hasChildren) throw new Exception(format("tag '%s' at line %s has no children", walker.tag.name, walker.tag.line));

      this.walker = walker;
      this.depth = walker.tag.depth + 1;

      walker.tagAvailable = parseSdlTag(walker.tag, &walker.sdl);
      
      if(walker.tag.depth != this.depth) {
	if(walker.tag.depth < this.depth) throw new Exception("possible code bug, tag said there was children but parsing the sdl revealed there was no children");

	throw new Exception(format("parseSdlTag changed tag depth from %s to %s, this should be impossible as the depth should only ever increase by 1", this.depth - 1, walker.tag.depth));
      }
    }

    @property
    bool empty() { return walker.empty || walker.tag.depth != this.depth; }
    @property
    size_t front() { return this.depth; }
    void popFront(bool skipChildren = false) {
      walker.popFront(this.depth, skipChildren);
    }
  }


}



void parseSdl(T, bool ignoreUnknown = false)(T t, inout(char)[] sdl) {
  inout(char)* start = sdl.ptr;
  inout(char)* limit = start + sdl.length;
  parseSdl!(T)(t, start, limit);
}
void parseSdl(T, bool ignoreUnknown = false)(ref T t, const(char)* start, const char* limit)  {
  Tag tag;

  writefln("Parsing sdl struct with the following members:");
  foreach(member; __traits(allMembers, T)) {
    writefln("  %s", member);
  }


 TAG_LOOP:
  while(parseSdlTag(&tag, start, limit)) {

    writefln("parseSdl: (depth %s) tag '%s'%s", tag.depth, tag.name,
	     tag.hasChildren ? " (has children)" : "");


    foreach(member; __traits(allMembers, T)) {
      if(tag.name == member) {
	writefln("matched member '%s'", member);
	continue TAG_LOOP;
      }
    }

    static if(ignoreUnknown) {
      writefln("parseSdl: error: no match for tag '%s'", tag.name);
    } else {
      throw new SdlParseException(tag.line, format("unknown tag '%s'", tag.name));
    }
    
  }

}


version(unittest)
{
  struct Dependency {
    string name;
    string version_;
  }
  // Example of parsing a configuration file
  struct Package {
    const(char)[] name;
    const(char)[] description;

    const(char)[][] authors;
    auto dependencies = appender!(Dependency[])();
    auto subPackages = appender!(Package[])();

    void reset() {
      name = null;
      description = null;
      authors = null;
      dependencies.clear();
      subPackages.clear();
    }

    bool opEquals(ref const Package p) {
      return
	name == p.name &&
	description == p.description &&
	authors == p.authors &&
	dependencies.data == p.dependencies.data &&
	subPackages.data == p.subPackages.data;
    }

    void parseSdlPackage(bool copySdl, string sdlText) {
      parseSdlPackage(setupSdlText(sdlText, copySdl));
    }
    void parseSdlPackage(char[] sdlText) {
      Tag tag;
      auto sdl = SdlWalker(&tag, sdlText);
      for(;!sdl.empty; sdl.popFront()) {

	writefln("[sdl] (depth %s) tag '%s'%s", tag.depth, tag.name,
		 tag.hasChildren ? "(has children)" : "");
	
	if(tag.name == "name") {

	  if(this.name != null) tag.throwIsDuplicate();
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.enforceOneValue(this.name);
	  
	} else if(tag.name == "description") {

	  if(this.description != null) tag.throwIsDuplicate();
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.enforceOneValue(this.description);

	} else if(tag.name == "authors") {

	  if(this.authors !is null) tag.throwIsDuplicate();
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.enforceValues(this.authors);
	  
	} else {
	  
	  tag.throwIsUnknown();
	  
	}
      }

    }
  }
}


unittest
{
  mixin(scopedTest!"SdlWalker");

  void testPackage(bool copySdl, string sdlText, ref Package expectedPackage) 
  {
    Package parsedPackage;

    parsedPackage.parseSdlPackage(copySdl, sdlText);

    if(expectedPackage != parsedPackage) {
      writefln("Expected package: %s", expectedPackage);
      writefln(" but got package: %s", parsedPackage);
      assert(0);
    }
  }

  string sdl;
  Package expectedPackage;

  expectedPackage = Package("my-package", "an example sdl package",
			    ["Jonathan", "David", "Amy"]);

  testPackage(false, `
name        "my-package"
description "an example sdl package"
authors     "Jonathan" "David" "Amy"
`, expectedPackage);

  sdl = `
name        "my-package"
description "an example sdl package"

authors     "Jonathan" "David" "Amy"
`;



/+
  StdoutWriter stdoutWriter;
  Tag tag;
  while(tag.parse(sdl)) {
    tag.toSdl(stdoutWriter);
  }
+/
  
/+
  Package p;

  parseSdl(p, `name        "my-package"
description "an example sdl package"
authors     "Jonathan" "David" "Amy"
subPackage {
  name "my-sub-package"
}`);
+/

}
