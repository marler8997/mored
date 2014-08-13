/**
   $(P An SDL ($(LINK2 http://www.ikayzo.org/display/SDL/Home,Simple Declarative Language)) parser.
     Supports StAX/SAX style API. See $(D more.std.dom) for DOM style API.)

   Examples:
   --------------------------------
   void printTags(char[] sdl) {
       Tag tag;
       while(parseSdlTag(&sdl, &tag)) {
           writefln("(depth %s) tag '%s' values '%s' attributes '%s'",
               tag.depth, tag.name, tag.values.data, tag.attributes.data);
       }
   }

   struct Person {
       string name;
       ushort age;
       string[] nicknames;
       auto children = appender!(Person[])();
       void reset() {
           name = null;
           age = 0;
           nicknames = null;
           children.clear();
       }
       void parseFromSdl(ref SdlWalker walker) {
           tag.enforceNoValues();
           tag.enforceNoAttributes();
           reset();
           foreach(auto personWalker = walker.children();
                   !personWalker.empty; personWalker.popFront) {

               if(tag.name == "name") {

                   tag.enforceNoAttributes();
                   tag.enforceNoChildren();
                   tag.getOneValue(name);

               } else if(tag.name == "age") {

                   tag.enforceNoAttributes();
                   tag.enforceNoChildren();
                   tag.getOneValue(age);

               } else if(tag.name == "nicknames") {

                   tag.enforceNoAttributes();
                   tag.enforceNoChildren();
                   tag.getValues(nicknames);

               } else if(tag.name == "child") {



                   // todo implement

               } else tag.throwIsUnknown();
           }
       }
       void validate() {
           if(name == null) throw new Exception("person is missing the 'name' tag");
           if(age == 0) throw new Exception("person is missing the 'age' tag");
       }
   }

   void parseTags(char[] sdl) {
       struct Person {
           string name;
           ushort age;
           string[] nicknames;
           Person[] children;
           void reset() {
               name = null;
               age = 0;
               nicknames = null;
               children = null;
           }
           void validate() {
               if(name == null) throw new Exception("person is missing the 'name' tag");
               if(age == 0) throw new Exception("person is missing the 'age' tag");
           }
       }
       auto people = appender(Person[])();
       Person person;

       Tag tag;
       for(auto walker = SdlWalker(&tag, sdl); !walker.empty; walker.popFront) {
           if(tag.name == "person") {

               tag.enforceNoValues();
               tag.enforceNoAttributes();
               person.reset();
               person.validate();
               people.put(person);

           } else tag.throwIsUnknown();
       }
   }

   --------------------------------
   TODO: finish unit tests
   TODO: implement multiline comments
   TODO: implement numbers
   TODO: write a generic input sdl parser that uses parseSdlTag
   TODO: support some sort of reflection
   TODO: possibly add lookup table to check for things like isID/isIDStart

   Authors: Jonathan Marler, johnnymarler@gmail.com
   License: use freely for any purpose
 */


module more.sdl;

import std.array;
import std.string;
import std.range;
import std.conv;
import std.bitmanip;

import std.c.string: memmove;

import more.common;
import more.utf8;

version(unittest)
{
  import std.stdio;
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


/// Embodies all the information about a single tag.
/// It does not contain any information about its children because that part of the sdl would not have been parsed yet.
/// It is used directly for the StAX/SAX APIs but not for the DOM API.
struct Tag {
  // These bitfields set flags to support non-standard
  // sdl.  The default value 0 will disable all flags
  // so the parser only allows standard sdl;
  mixin(bitfields!(
		   // Normally SDL only allows a tag to have attributes after all its
		   // values.  This option allows them to be mixed i.e.
		   //     tag attr="my-value" "another-value" would be valid
		   bool,  "allowMixedValuesAndAttributes", 1,
		   // Allows tag braces to appear after any number of newlines
		   bool,  "allowBraceAfterNewline", 1,
		   // Prevents sdl from modifying the given text for things such as
		   // processing escaped strings
		   bool,  "preserveSdlText", 1,
		   // TODO: maybe add an option to specify that any values accessed should be copied to new buffers
		   // NOTE: Do not add an option to prevent parseSdlTag from throwing exceptions when the input has ended.
		   //       It may have been useful for an input buffered object, however, the buffered input object will
		   //       need to know when it has a full tag anyway so the sdl will already contain the characters to end the tag.
		   //       Or in the case of braces on the next line, if the tag has alot of whitespace until the actual end-of-tag
		   //       delimiter, the buffered input reader can insert a semi-colon or open_brace to signify the end of the tag
		   //       earlier.
		   ubyte, "", 5));

  void resetOptions() {
    this.allowMixedValuesAndAttributes = false;
    this.allowBraceAfterNewline = false;
    this.preserveSdlText = false;
  }

  /// The depth of the tag, all root tags start at depth 0.
  size_t depth = 0;

  /// The line number of the SDL parser after parsing this tag.
  uint line    = 1;

  /// The namespace of the tag
  const(char)[] namespace;
  /// The name of the tag
  const(char)[] name;
  /// The values of the tag
  auto values     = appender!(const(char)[][])();
  /// The attributes of the tag
  auto attributes = appender!(Attribute[])();
  /// Indicates the tag has an open brace
  private bool hasOpenBrace;

  version(unittest)
  {
    // This function is only so unit tests can create Tags to compare
    // with tags parsed from the parseSdlTag function. This constructor
    // should never be called in production code
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

  /// Gets the tag ready to parse a new sdl tree by resetting the depth and the line number.
  /// It is unnecessary to call this before parsing the first sdl tree but would not be harmful.
  /// It does not reset the namespace/name/values/attributes because those will
  /// be reset by the parser on the next call to parseSdlTag when it calls resetForNextTag().
  void resetForReuse() {
    depth = 0;
    line = 1;
  }

  /// Resets the tag state to get ready to parse the next tag.
  /// Should only be called by the parseSdlTag function.
  /// This will clear the namespace/name/values/attributes and increment the depth if the current tag
  /// had an open brace.
  void resetForNextTag()
  {
    this.namespace.length = 0;
    this.name = null;
    if(hasOpenBrace) {
      hasOpenBrace = false;
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

  /// Returns: true if the tag namespaces/names/values/attributes are
  ///          the same even if the depth/line/options are different.
  bool opEquals(ref Tag other) {
    return
      namespace == other.namespace &&
      name == other.name &&
      values.data == other.values.data &&
      attributes.data == other.attributes.data;
  }

  /// Returns: A string of the Tag not including it's children.  The string will be valid SDL
  ///          by itself but will not include the open brace if it has one.  Use toSdl for that.
  string toString() {
    string str = "";
    if(namespace.length) {
      str ~= namespace;
      str ~= name;
    }
    if(name != "content" || (values.data.length == 0 && attributes.data.length == 0)) {
      str ~= name;
    }
    foreach(value; values.data) {
      str ~= ' ';
      str ~= value;
    }
    foreach(attribute; attributes.data) {
      str ~= ' ';
      if(attribute.namespace.length) {
	str ~= attribute.namespace;
	str ~= ':';
      }
      str ~= attribute.id;
      str ~= '=';
      str ~= attribute.value;
    }
    return str;
  }

  /// Writes the tag as standard SDL to sink.
  /// It will write the open brace '{' but since the tag does not have a knowledge
  /// about it's children, its up to the caller to write the close brace '}' after it
  /// writes the children to the sink.
  void toSdl(S, string indent = "    ")(S sink) if(isOutputRange!(S,const(char)[])) {
    //writefln("[DEBUG] converting to sdl namespace=%s name=%s values=%s attr=%s",
    //namespace, name, values.data, attributes.data);
    for(auto i = 0; i < depth; i++) {
      sink.put(indent);
    }
    if(namespace.length) {
      sink.put(namespace);
      sink.put(":");
    }
    if(name != "content" || (values.data.length == 0 && attributes.data.length == 0))
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
    if(hasOpenBrace) {
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
  void getOneValue(T)(ref T t) {
    if(values.data.length != 1)
      throw new SdlParseException(line, format("tag '%s' must have exactly 1 value but had %s", name, values.data.length));
    const(char)[] literal = values.data[0];
    static if( isSomeString!T ) {
      if(!t.empty) throwIsDuplicate();
      if(literal[0] != '"') throw new SdlParseException(line, format("tag '%s' must have exactly one string literal but had another literal type", name));
      t = literal[1..$-1]; // remove surrounding quotes
/+
    } else static if( isUnsigned!T ) {
	//if(literal[0] == '-') throw new SdlParseException(line, format("tag '%s' cannot convert the negative sdl value '%s' to %s", name, literal, typeid(T)));
	return to!T(literal);
+/
//    } else static if( isNumeric(T) ) {
//	return to!T(literal);
    } else {
      t = to!T(literal);
      //assert(0, format("Cannot convert sdl literal to D '%s' type", typeid(T)));
    }
  }
/+
  const(char)[][] getValues() {
    if(values.data.length == 0) throw new SdlParseException(line, format("tag '%s' must have at least 1 value", name));
    //writefln("[DEBUG] values.data.length = %s", values.data.length);
    const(char)[][] newValues = new const(char)[][values.data.length];
    newValues[] = values.data;
    return newValues;
  }
+/

  void getValues(T, bool allowAppend=false)(ref T[] t, size_t minCount = 1) {
    if(values.data.length < minCount) throw new SdlParseException(line, format("tag '%s' must have at least %s value(s)", name, minCount));

    size_t arrayOffset;
    if(t.ptr is null) {
      arrayOffset = 0;
      t = new T[values.data.length];
    } else if(allowAppend) {
      arrayOffset = t.length;
      t.length += values.data.length;
    } else throwIsDuplicate();

    foreach(literal; values.data) {
      static if( isSomeString!T ) {
	if(literal[0] != '"') throw new SdlParseException(line, format("tag '%s' must have exactly one string literal but had another literal type", name));
	t[arrayOffset++] = literal[1..$-1]; // remove surrounding quotes
      } else {
	assert(0, format("Cannot convert sdl literal to D '%s' type", typeid(T)));
      }
    }
  }


  void enforceNoValues() {
    if(values.data.length) throw new SdlParseException(line, format("tag '%s' cannot have any values", name));
  }
  void enforceNoAttributes() {
    if(attributes.data.length) throw new SdlParseException(line, format("tag '%s' cannot have any attributes", name));
  }
  void enforceNoChildren() {
    if(hasOpenBrace) throw new SdlParseException(line, format("tag '%s' cannot have any children", name));
  }


}

version = use_lookup_tables;

bool isIDStart(dchar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
/+
 The lookup table doesn't seem to be as fast here, maybe this case I should just compare the ranges
  version(use_lookup_tables) {
    return (c < sdlLookup.length) ? ((sdlLookup[c] & idStartFlag) != 0) : false;
  } else {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
  }
+/
}
bool isID(dchar c) {
  version(use_lookup_tables) {
    return (c < sdlLookup.length) ? ((sdlLookup[c] & sdlIDFlag) != 0) : false;
  } else {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '$';
  }
}
enum tooManyEndingBraces = "too many ending braces '}'";
enum noEndingQuote = "string missing ending quote";
enum invalidBraceFmt = "found '{' on a different line than its tag '%s'.  fix the sdl by moving '{' to the same line";
enum mixedValuesAndAttributesFmt = "SDL values cannot appear after attributes, bring '%s' in front of the attributes for tag '%s'";
enum notEnoughCloseBracesFmt = "reached end of sdl but missing %s close brace(s) '}'";


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
  if(range.length == 3) {
    return range ~ ":" ~ s[1] ~ rangeInitializersNext(s);
  }
  char min = range[1];
  char max = range[5];
  return arrayRange(min, max, s[1]) ~ rangeInitializersNext(s);
}
string rangeInitializersNext(string[] s...) {
  if(s.length <= 2) return "]";
  return ","~rangeInitializersCurrent(s[2..$]);
}


enum ubyte sdlIDFlag      = 0x01;
enum ubyte sdlNumberFlag  = 0x02;
version(use_lookup_tables) {
  mixin("private __gshared ubyte[256] sdlLookup = "~rangeInitializers
	("'_'"    , "sdlIDFlag",

	 "'a'"    , "sdlIDFlag",
	 "'b'"    , "sdlIDFlag | sdlNumberFlag",
	 "'c'"    , "sdlIDFlag",
	 "'d'"    , "sdlIDFlag | sdlNumberFlag",
	 "'e'"    , "sdlIDFlag",
	 "'f'"    , "sdlIDFlag | sdlNumberFlag",
	 "'g'-'k'", "sdlIDFlag",
	 "'l'"    , "sdlIDFlag | sdlNumberFlag",
	 "'m'-'z'", "sdlIDFlag",

	 "'A'"    , "sdlIDFlag",
	 "'B'"    , "sdlIDFlag | sdlNumberFlag",
	 "'C'"    , "sdlIDFlag",
	 "'D'"    , "sdlIDFlag | sdlNumberFlag",
	 "'E'"    , "sdlIDFlag",
	 "'F'"    , "sdlIDFlag | sdlNumberFlag",
	 "'G'-'K'", "sdlIDFlag",
	 "'L'"    , "sdlIDFlag | sdlNumberFlag",
	 "'M'-'Z'", "sdlIDFlag",

	 "'0'-'9'", "sdlIDFlag | sdlNumberFlag",
	 "'-'"    , "sdlIDFlag",
	 "'.'"    , "sdlIDFlag | sdlNumberFlag",
	 "'$'"    , "sdlIDFlag",
	 )~";");
}

/// Parses one SDL tag (not including its children) from sdlText saving slices for every
/// name/value/attribute to the given tag struct.
/// This function assumes that sdlText contains at least one full SDL _tag.
/// The only time this function will allocate memory is if the value/attribute appenders
/// in the tag struct are not large enough to hold all the values.
/// Because of this, after the tag values/attributes are populated, it is up to the caller to copy
/// any memory they wish to save unless sdlText is not going to be garbage collected.
/// Note: this function does not handle the UTF-8 bom because it doesn't make sense to re-check
///       for the BOM after every tag.
/// Params:
///   tag = An address to a Tag structure to save the sdl information.
///   sdlText = An address to the sdl text character array.
///             the function will move the front of the slice foward past
///             any sdl that was parsed.
/// Returns: true if a tag was found, false otherwise
/// Throws: SdlParseException or Utf8Exception
bool parseSdlTag(Tag* tag, char[]* sdlText)
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
  const(char)[] literal;

  void enforceNoMoreTags() {
    if(tag.depth > 0) throw new SdlParseException(tag.line, format(notEnoughCloseBracesFmt, tag.depth));
  }

  void readNext()
  {
    cpos = next;
    c = decodeUtf8(next, limit);
  }

  bool isIDStart() {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
/+
    The lookup table actually seems to be slower in this case
    version(use_lookup_tables) {
      return (c < sdlLookup.length) ? ((sdlLookup[c] & idStartFlag) != 0) : false;
    } else {
      return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    }
+/
  }
  bool isID() {
    version(use_lookup_tables) {
      return c < sdlLookup.length && ((sdlLookup[c] & sdlIDFlag) != 0);
    } else {
      return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '$';
    }
  }
  bool isNumber() {
    version(use_lookup_tables) {
      return c < sdlLookup.length && ((sdlLookup[c] & sdlNumberFlag) != 0);
    } else {
      implement("isNumber without lookup table");
      //return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '$';
    }
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
      if(!isID()) return;
    }
  }


  // expects c/cpos to point at the first character after the id
  // Returns: true if the id is actually a value
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

  // Returns: true if a newline was found
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

      auto startOfNumber = cpos;
      while(true) {
	if(next >= limit) {
	  literal = startOfNumber[0..next-startOfNumber];
	  cpos = limit;
	  break;
	}
	readNext();
	if(!isNumber()) {
	  literal = startOfNumber[0..cpos-startOfNumber];
	  break;
	}
      }
      
      //implement("sdl numbers");

    } else if(c == 'n') {

      // NOTE: I need to make sure that I can treat the keyword literals
      //       as ascii.  This wil not work if the characters are encoded
      //       using UTF-8 multibyte characters when they don't need to be.
      if(limit >= next + 3) {
	if(cpos[1..4] == "ull") {
	  literal = "null";
	  cpos += 4;
	  next = cpos;
	  c = decodeUtf8(next, limit);
	}
      }
    } else if(c == 't') {

      if(limit >= next + 3) {
	if(cpos[1..4] == "rue") {
	  literal = "true";
	  cpos += 4;
	  next = cpos;
	  c = decodeUtf8(next, limit);
	}
      }

    } else if(c == 'f') {

      if(limit >= next + 4) {
	if(cpos[1..5] == "alse") {
	  literal = "false";
	  cpos += 5;
	  next = cpos;
	  c = decodeUtf8(next, limit);
	}
      }

    } else if(c == 'o') {

      if(limit >= next + 1 && cpos[1] == 'n') {
	literal = "on";
	cpos += 2;
	next = cpos;
	c = decodeUtf8(next, limit);
      } else if(limit >= next + 2 && cpos[1..3] == "ff") {
	literal = "off";
	cpos += 3;
	next = cpos;
	c = decodeUtf8(next, limit);
      }


    } else if(c == '\'') {

      implement("sing-quoted characters");

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
    if(isIDStart()) {

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
	  readNext();

	  if(!isIDStart())  {
	    tag.name = "content";
	    //throw new SdlParseException(
	    //tag.line, format("expected alphanum or '_' after colon ':' but got '%s'", c));
	  } else {
	    parseID();
	    tag.setName(startOfTag, cpos);
	    if(cpos >= limit) goto RETURN_TAG;
	  }

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
    } else if(c == ':') {
      throw new SdlParseException(tag.line, "expected tag or '}' but got ':'");
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
	  tag.hasOpenBrace = true;
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
	tag.hasOpenBrace = true; // depth will be incremented at the next parse
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
      if(isIDStart()) {

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
	  startOfID = next;
	  c = decodeUtf8(next, limit);
	  if(!isIDStart()) throw new SdlParseException(tag.line, "an sdl id must follow the colon ':' character");

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



version(unittest)
{
  char[2048] sdlBuffer;
  char[sdlBuffer.length] sdlBuffer2;
  char[] setupSdlText(const(char[]) sdlText, bool copySdl)
  {
    if(!copySdl) return cast(char[])sdlText;

    if(sdlText.length >= sdlBuffer.length) throw new Exception(format("attempting to copy sdl of length %s but sdlBuffer is only of length %s", sdlText.length, sdlBuffer.length));
    sdlBuffer[0..sdlText.length] = sdlText;
    return sdlBuffer[0..sdlText.length];
  }

  struct SdlBuffer2Sink
  {
    size_t offset;
    @property
    char[] slice() { return sdlBuffer2[0..offset]; }
    void put(inout(char)[] value) {
      sdlBuffer2[offset..offset+value.length] = value;
      offset += value.length;
    }
  }

}


unittest
{
  //return; // Uncomment to disable these tests

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

  void testParseSdl(bool reparse = true)(bool copySdl, const(char)[] sdlText, Tag[] expectedTags...)
  {
    size_t previousDepth = size_t.max;
    SdlBuffer2Sink buffer2Sink;

    auto escapedSdlText = escape(sdlText);

    debug {
      static if(reparse) {
	writefln("[TEST] testing sdl              : %s", escapedSdlText);
      } else {
	writefln("[TEST] testing sdl (regenerated): %s", escapedSdlText);
      }
    }

    char[] next = setupSdlText(sdlText, copySdl);

    parsedTag.resetForReuse();


    try {

      for(auto i = 0; i < expectedTags.length; i++) {
	if(!parseSdlTag(&parsedTag, &next)) {
	  writefln("Expected %s tag(s) but only got %s", expectedTags.length, i);
	  assert(0);
	}

	static if(reparse) {
	  if(previousDepth != size_t.max) {
	    while(previousDepth > parsedTag.depth) {
	      buffer2Sink.put("}");
	      previousDepth--;
	    }
	  }
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

	// put the tag into the buffer2 sink to reparse again after
	static if(reparse) {
	  parsedTag.toSdl(&buffer2Sink);
	  previousDepth = parsedTag.depth;
	  if(parsedTag.hasOpenBrace) previousDepth++;
	}
      }

      if(parseSdlTag(&parsedTag, &next)) {
	writefln("Expected %s tag(s) but got at least one more (depth=%s, name='%s')",
		 expectedTags.length, parsedTag.depth, parsedTag.name);
	assert(0);
      }
      
    } catch(SdlParseException e) {
      writefln("[TEST] this sdl threw an unexpected SdlParseException: '%s'", escape(sdlText));
      writeln(e);
      assert(0);
    } catch(Exception e) {
      writefln("[TEST] this sdl threw an unexpected Exception: '%s'", escape(sdlText));
      writeln(e);
      assert(0);
    }

    static if(reparse) {
      if(previousDepth != size_t.max) {
	while(previousDepth > parsedTag.depth) {
	  buffer2Sink.put("}");
	  previousDepth--;
	}
      }

      if(buffer2Sink.slice != sdlText &&
	 (buffer2Sink.slice.length && buffer2Sink.slice[0..$-1] != sdlText)) {
	testParseSdl!false(false, buffer2Sink.slice, expectedTags);
      }
    }

  }

  void testInvalidSdl(bool copySdl, const(char)[] sdlText, SdlErrorType expectedErrorType = SdlErrorType.unknown) {
    auto escapedSdlText = escape(sdlText);
    debug writefln("[TEST] testing invalid sdl '%s'", escapedSdlText);

    SdlErrorType actualErrorType = SdlErrorType.unknown;

    char[] next = setupSdlText(sdlText, copySdl);

    parsedTag.resetForReuse();
    try {
      while(parseSdlTag(&parsedTag, &next)) { }
      writefln("Error: invalid sdl was successfully parsed: %s", sdlText);
      assert(0);
    } catch(SdlParseException e) {
      debug writefln("[TEST]    got expected error: %s", e.msg);
      actualErrorType = e.type;
    } catch(Utf8Exception e) {
      debug writefln("[TEST]    got expected error: %s", e.msg);
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

  // TODO: test this using the allowBracesAfterNewline option
  //  testParseSdl(false, "tag /*\n\n*/{ child }", Tag("tag"), Tag("child"));


  testParseSdl(false, "a", Tag("a"));
  testParseSdl(false, "ab", Tag("ab"));
  testParseSdl(false, "abc", Tag("abc"));
  testParseSdl(false, "firsttag", Tag("firsttag"));
  testParseSdl(false, "funky._-$tag", Tag("funky._-$tag"));


  {
    auto prefixes = ["", " ", "\t", "--comment\n"];
    foreach(prefix; prefixes) {
      testInvalidSdl(false, prefix~":");
    }
  }

  auto namespaces = ["a:", "ab:", "abc:"];
  foreach(namespace; namespaces) {
    testParseSdl(false, namespace, Tag(namespace~"content"));
    testParseSdl(false, namespace~" ", Tag(namespace~"content"));
    testParseSdl(false, namespace~"\t", Tag(namespace~"content"));
    testParseSdl(false, namespace~"\n", Tag(namespace~"content"));
    testParseSdl(false, namespace~";", Tag(namespace~"content"));
    testParseSdl(false, namespace~`"value"`, Tag(namespace~"content", `"value"`));
    //testParseSdl(false, namespace~`attr=null`, Tag(namespace~"content", "attr=null"));
  }




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

  testParseSdl(false, `tag"value"`, Tag("tag", `"value"`));


  //
  // Handling the backslash '\' character
  //
  testInvalidSdl(false, "\\"); // slash must in the context of a tag
  testInvalidSdl(false, `tag \ x`);

  testParseSdl(false, "tag\\", Tag("tag")); // Make sure this is valid sdl
  testParseSdl(false, "tag \\  \n \\ \n \"hello\"", Tag("tag", `"hello"`));

  //
  // Test the keywords (white box tests trying to attain full code coverage)
  //
  auto keywords = ["null", "true", "false", "on", "off"];

  foreach(keyword; keywords) {
    testParseSdl(false, keyword, Tag("content", keyword));
  }

  namespaces = ["", "n:", "namespace:"];
  foreach(namespace; namespaces) {
    sdlBuffer[0..namespace.length] = namespace;
    auto afterTagName = namespace.length + 4;
    sdlBuffer[namespace.length..afterTagName] = "tag ";
    string expectedTagName = namespace~"tag";

    foreach(keyword; keywords) {
      for(auto cutoff = 1; cutoff < keyword.length; cutoff++) {
	sdlBuffer[afterTagName..afterTagName+cutoff] = keyword[0..cutoff];
	testInvalidSdl(false, sdlBuffer[0..afterTagName+cutoff]);
      }
    }
    auto suffixes = [";", " \t;", "\n", "{}", " \t {\n }"];
    foreach(keyword; keywords) {
      auto limit = afterTagName+keyword.length;

      sdlBuffer[afterTagName..limit] = keyword;
      testParseSdl(false, sdlBuffer[0..limit], Tag(expectedTagName, keyword));

      foreach(suffix; suffixes) {
	sdlBuffer[limit..limit+suffix.length] = suffix;
	testParseSdl(false, sdlBuffer[0..limit+suffix.length], Tag(expectedTagName, keyword));
      }
    }
    foreach(keyword; keywords) {

      foreach(attrNamespace; namespaces) {

	for(auto cutoff = 1; cutoff <= keyword.length; cutoff++) {
	  auto limit = afterTagName + attrNamespace.length;
	  sdlBuffer[afterTagName..limit] = attrNamespace;
	  limit += cutoff;
	  sdlBuffer[limit - cutoff..limit] = keyword[0..cutoff];
	  sdlBuffer[limit..limit+8] = `="value"`;
	  testParseSdl(false, sdlBuffer[0..limit+8], Tag(expectedTagName, format(`%s%s="value"`, attrNamespace, keyword[0..cutoff])));

	  foreach(otherKeyword; keywords) {
	    sdlBuffer[limit+1..limit+1+otherKeyword.length] = otherKeyword;
	    testParseSdl(false, sdlBuffer[0..limit+1+otherKeyword.length],
			 Tag(expectedTagName, format("%s%s=%s", attrNamespace, keyword[0..cutoff], otherKeyword)));
	  }
	}

      }

    }
  }

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
  debug writefln("[TEST] setting allowMixedValuesAndAttributes = true;");
  parsedTag.allowMixedValuesAndAttributes = true;
  foreach(test; mixedValuesAndAttributesTests) {
    testParseSdl(test.copySdl, test.sdlText, test.expectedTags);
  }
  debug writefln("[TEST] resetting options to default");
  parsedTag.resetOptions();


  {
    enum numberPrefixes = ["","-"];
    enum numberPostfixes = ["l", "L", "f", "F", "d", "D", "bd", "BD"];
    enum sdlPostfixes = ["", " ", ";", "\n"];
    auto numbers = ["0", "12", "9876", "5432", /*".1",*/ "0.1", "12.4", /*"1.",*/ "8.04",  "123.l"];

    foreach(prefix; numberPrefixes) {
      foreach(postfix; numberPostfixes) {
	foreach(number; numbers) {

	  auto testNumber = prefix~number~postfix;

	  //testInvalidSdl(false, "tag "~testNumber~"=");

	  foreach(sdlPostfix; sdlPostfixes) {
	    testParseSdl(false, "tag "~testNumber~sdlPostfix, Tag("tag", testNumber));
	  }
	}
      }
    }
  }


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
  debug writefln("[TEST] setting allowBraceAfterNewline = true");
  parsedTag.allowBraceAfterNewline = true;
  foreach(test; braceAfterNewlineTests) {
    testParseSdl(test.copySdl, test.sdlText, test.expectedTags);
  }
  debug writefln("[TEST] resetting options to default");
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
}

/// Assists in walking an SDL tree which supports the StAX method of parsing.
/// Examples:
/// ---
/// Tag tag;
/// SdlWalker walker = SdlWalker(&tag, sdl);
/// while(walker.pop()) {
///     // use tag to process the current tag
///     
///     auto depth = tag.childrenDepth();
///     while(walker.pop(depth)) {
///         // process tag again as a child tag
///     }
///
/// }
/// ---
struct SdlWalker
{
  /// A pointer to the tag structure that will be populated after parsing every tag.
  Tag* tag;

  // The sdl text that has yet to be parsed.   
  private char[] sdl;

  // Used for when a child walker has popped a parent tag
  bool tagAlreadyPopped;

  this(Tag* tag, char[] sdl) {
    this.tag = tag;
    this.sdl = sdl;
  }

  /// Parses the next tag at the given depth.
  /// Returns: true if it parsed a tag at the given depth and false if there are no more
  ///          tags at the given depth. If it is depth 0 it means the sdl has been fully parsed.
  /// Throws: Exception if the current tag has children and they were not parsed
  ///         and allowSkipChildren is set to false.
  bool pop(size_t depth = 0, bool allowSkipChildren = false) {
    if(tagAlreadyPopped) {
      if(depth < tag.depth) throw new Exception("possible code bug here?");
      if(tag.depth == depth) {
	tagAlreadyPopped = false;
      }
    }

    while(true) {
      size_t previousDepth;
      const(char)[] previousName;

      if(!allowSkipChildren) {
	previousDepth = tag.depth;
	previousName = tag.name;
      }

      if(!parseSdlTag(this.tag, &sdl)) {
	assert(tag.depth == 0, format("code bug: parseSdlTag returned end of input but tag.depth was %s (not 0)", tag.depth));
	return false;
      }

      if(this.tag.depth == depth) return true;

      // Check if it is the end of this set of children
      if(this.tag.depth < depth) {
	tagAlreadyPopped = true;
	return false;
      }
      
      if(!allowSkipChildren) throw new Exception(format("forgot to call children on tag '%s' at depth %s", previousName, previousDepth));
    }
  }

  public size_t childrenDepth() { return tag.depth + 1; }

/+
  public ChildrenWalker children() {
    return ChildrenWalker(&this);
  }

  struct ChildrenWalker {
    SdlWalker* walker;
    const size_t depth;

    this(SdlWalker* walker) {
      //if(!walker.tag.hasOpenBrace) throw new Exception(format("tag '%s' at line %s has no children", walker.tag.name, walker.tag.line));

      this.walker = walker;
      this.depth = walker.tag.depth + 1;
    }

    bool pop(bool allowSkipChildren = false) {
      return walker.pop(this.depth, allowSkipChildren);
    }
  }
+/

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
	     tag.hasOpenBrace ? " (has children)" : "");


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
      while(sdl.pop()) {

	writefln("[sdl] (depth %s) tag '%s'%s", tag.depth, tag.name,
		 tag.hasOpenBrace ? "(has children)" : "");

	if(tag.name == "name") {

	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(this.name);

	} else if(tag.name == "description") {

	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(this.description);

	} else if(tag.name == "authors") {

	  if(this.authors !is null) tag.throwIsDuplicate();
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getValues(this.authors);

	} else tag.throwIsUnknown();

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




unittest
{
  mixin(scopedTest!"SdlWalkerOnPerson");

  struct Person {
    const(char)[] name;
    ushort age;
    const(char)[][] nicknames;
    Person[] children;
    void reset() {
      name = null;
      age = 0;
      nicknames = null;
      children.clear();
    }
    bool opEquals(ref const Person p) {
      return
	name == p.name &&
	age == p.age &&
	nicknames == p.nicknames &&
	children == p.children;
    }
    string toString() {
      return format("Person(\"%s\", %s, %s, %s)", name, age, nicknames, children);
    }
    void validate() {
      if(name is null) throw new Exception("person is missing the 'name' tag");
      if(age == 0) throw new Exception("person is missing the 'age' tag");
    }
    void parseFromSdl(ref SdlWalker walker) {
      auto tag = walker.tag;

      tag.enforceNoValues();
      tag.enforceNoAttributes();

      reset();

      auto childBuilder = appender!(Person[])();

      auto depth = walker.childrenDepth();
      while(walker.pop(depth)) {
      //auto childrenWalker = walker.children();
      //while(childrenWalker.pop()) {

	stdout.flush();

	if(tag.name == "name") {

	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(name);

	} else if(tag.name == "age") {

	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(age);

	} else if(tag.name == "nicknames") {

	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getValues(nicknames);

	} else if(tag.name == "child") {

	  Person child = Person();
	  child.parseFromSdl(walker, );
	  childBuilder.put(child);

	} else tag.throwIsUnknown();

      }

      this.children = childBuilder.data.dup;
      childBuilder.clear();
      validate();
    }
  }

  Appender!(Person[]) parsePeople(char[] sdl) {
    auto people = appender!(Person[])();
    Person person;

    Tag tag;
    auto walker = SdlWalker(&tag, sdl);
    while(walker.pop()) {
      if(tag.name == "person") {

	person.parseFromSdl(walker);
	people.put(person);

      } else tag.throwIsUnknown();
    }

    return people;
  }

  void testParsePeople(bool copySdl, string sdlText, Person[] expectedPeople...)
  {
    Appender!(Person[]) parsedPeople;
    try {

      parsedPeople = parsePeople(setupSdlText(sdlText, copySdl));

    } catch(Exception e) {
      writefln("the following sdl threw an unexpected exception: %s", sdlText);
      writeln(e);
      assert(0);
    }

    if(expectedPeople.length != parsedPeople.data.length) {
      writefln("Expected: %s", expectedPeople);
      writefln(" but got: %s", parsedPeople.data);
      assert(0);
    }
    for(auto i = 0; i < expectedPeople.length; i++) {
      Person expectedPerson = expectedPeople[i];
      if(expectedPerson != parsedPeople.data[i]) {
	writefln("Expected: %s", expectedPeople);
	writefln(" but got: %s", parsedPeople.data);
	assert(0);
      }
    }

  }

  auto childBuilder = appender!(Person[])();


  childBuilder.clear();
  childBuilder.put(Person("Jack", 6, ["Little Jack"]));

  testParsePeople(false, `
person {
    name "Robert"
    age 29
    nicknames "Bob" "Bobby"
    child {
        name "Jack"
        age 6
        nicknames "Little Jack"
    }
}`, Person("Robert", 29, ["Bob", "Bobby"], [Person("Jack", 6, ["Little Jack"])]));

}
