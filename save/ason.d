/**
   $(P An $(LINK2 https://github.com/marler8997/mored/wiki/ASON-(Application-Specific-Object-Notation), ASON) parser.
    )

   Examples:
   --------------------------------
   // Possible API:
   serializeToAson(R,T)(R sink, T value);
   deserializeAson(T,R)(R input);

   Ason parseAson(R)(ref R range, int* line = null);
   Ason parseAson(string text);

   void writeAson(R, bool compressed)(ref R sink, in Json json, size_t level);

   struct Ason : represents single Ason value
   struct AsonSerializer : serializer for Ason
   struct AsonStringSerializer : serializer for a range based plain ASON string

   --------------------------------
   Authors: Jonathan Marler, johnnymarler@gmail.com
   License: use freely for any purpose
 */

module more.ason;

import std.array;
import std.string;
import std.range;
import std.conv;
import std.bitmanip;
import std.traits;

import std.c.string: memmove;

import more.common;
import more.utf8;

version(unittest_ason)
{
  import std.stdio;
}

enum AsonErrorType {
  unknown,
  braceAfterNewline,
  mixedValuesAndAttributes,
}
class AsonParseException : Exception
{
  AsonErrorType type;
  uint lineInAson;
  this(uint lineInAson, string msg, string file = __FILE__, size_t codeLine = __LINE__) {
    this(AsonErrorType.unknown, lineInAson, msg, file, codeLine);
  }
  this(AsonErrorType errorType, uint lineInAson, string msg, string file = __FILE__, size_t codeLine = __LINE__) {
    super((lineInAson == 0) ? msg : "line "~to!string(lineInAson)~": "~msg, file, codeLine);
    this.type = errorType;
    this.lineInAson = lineInAson;
  }
}

struct Attribute {
  const(char)[] namespace;
  const(char)[] id;
  const(char)[] value;
}


struct Ason {
}


/// Embodies all the information about a single tag.
/// It does not contain any information about its children because that part of the sdl would not have been parsed yet.
/// It is used directly for the StAX/SAX APIs but not for the DOM or Reflection APIs.
struct Tag {

  // A bifield of flags used to pass extra options to parseAsonTag.
  // Used to accept/reject different types of SDL or cause parseAsonTag to
  // behave differently like preventing it from modifying the sdl text.
  private ubyte flags;
  
  /// Normally SDL only allows a tag's attributes to appear after all it's values.
  /// This flag causes parseAsonTag to allow values/attributes to appear in any order, i.e.
  ///     $(D tag attr="my-value" "another-value" # would be valid)
  @property @safe bool allowMixedValuesAndAttributes() pure nothrow const { return (flags & 1U) != 0;}
  @property @safe void allowMixedValuesAndAttributes(bool v) pure nothrow { if (v) flags |= 1U;else flags &= ~1U;}

  /// Causes parseAsonTag to allow a tag's open brace to appear after any number of newlines
  @property @safe bool allowBraceAfterNewline() pure nothrow const        { return (flags & 2U) != 0;}
  @property @safe void allowBraceAfterNewline(bool v) pure nothrow        { if (v) flags |= 2U;else flags &= ~2U;}

  /// Causes parseAsonTag to throw an exception if it finds any number literals
  /// with postfix letters indicating the type
  @property @safe bool rejectTypedNumbers() pure nothrow const            { return (flags & 4U) != 0;}
  @property @safe void rejectTypedNumbers(bool v) pure nothrow            { if (v) flags |= 4U;else flags &= ~4U;}

  /// Causes parseAsonTag to set the tag name to null instead of "content" for anonymous tags.
  /// This allows the application to differentiate betweeen "content" tags and anonymous tags.
  @property @safe bool anonymousTagNameIsNull() pure nothrow const        { return (flags & 8U) != 0;}
  @property @safe void anonymousTagNameIsNull(bool v) pure nothrow        { if (v) flags |= 8U;else flags &= ~8U;}

  /// Prevents parseAsonTag from modifying the given sdl text for things such as
  /// processing escaped strings
  @property @safe bool preserveAsonText() pure nothrow const               { return (flags & 16U) != 0;}
  @property @safe void preserveAsonText(bool v) pure nothrow               { if (v) flags |= 16U;else flags &= ~16U;}


  // TODO: maybe add an option to specify that any values accessed should be copied to new buffers
  // NOTE: Do not add an option to prevent parseAsonTag from throwing exceptions when the input has ended.
  //       It may have been useful for an input buffered object, however, the buffered input object will
  //       need to know when it has a full tag anyway so the sdl will already contain the characters to end the tag.
  //       Or in the case of braces on the next line, if the tag has alot of whitespace until the actual end-of-tag
  //       delimiter, the buffered input reader can insert a semi-colon or open_brace to signify the end of the tag
  //       earlier.
 


  /// For now an alias for useStrictAson. Use this function if you want your code to always use
  /// the default mode whatever it may become.
  alias useStrictAson useDefaultAson;

  /// This is the default mode.
  /// $(OL
  ///   $(LI Causes parseAsonTag to throw AsonParseException if a tag's open brace appears after a newline)
  ///   $(LI Causes parseAsonTag to throw AsonParseException if any tag value appears after any tag attribute)
  ///   $(LI Causes parseAsonTag to accept postfix characters after number literals.)
  ///   $(LI Causes parseAsonTag to set anonymous tag names to "content")
  /// )
  void useStrictAson() {
    this.allowMixedValuesAndAttributes = false;
    this.allowBraceAfterNewline = false;
    this.rejectTypedNumbers = false;
    this.anonymousTagNameIsNull = false;
  }
  /// $(OL
  ///   $(LI Causes parseAsonTag to throw AsonParseException if a tag's open brace appears after a newline)
  ///   $(LI Causes parseAsonTag to throw AsonParseException if any tag value appears after any tag attribute)
  ///   $(LI Causes parseAsonTag to accept postfix characters after number literals.)
  ///   $(LI Causes parseAsonTag to set anonymous tag names to "content")
  /// )
  void useLooseAson() {
    this.allowMixedValuesAndAttributes = true;
    this.allowBraceAfterNewline = true;
    this.rejectTypedNumbers = false;
    this.anonymousTagNameIsNull = false;
  }
  /// $(OL
  ///   $(LI Causes parseAsonTag to allow a tag's open brace appears after any number of newlines)
  ///   $(LI Causes parseAsonTag to allow tag values an attributes to mixed in any order)
  ///   $(LI Causes parseAsonTag to throw AsonParseException if a number literal has any postfix characters)
  ///   $(LI Causes parseAsonTag to set anonymous tag names to null)
  /// )
  void useProposedAson() {
    this.allowMixedValuesAndAttributes = true;
    this.allowBraceAfterNewline = true;
    this.rejectTypedNumbers = true;
    this.anonymousTagNameIsNull = true;
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
  bool hasOpenBrace;

/+
  version(unittest_ason)
  {
    // This function is only so unit tests can create Tags to compare
    // with tags parsed from the parseAsonTag function. This constructor
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
+/
  /// Gets the tag ready to parse a new sdl tree by resetting the depth and the line number.
  /// It is unnecessary to call this before parsing the first sdl tree but would not be harmful.
  /// It does not reset the namespace/name/values/attributes because those will
  /// be reset by the parser on the next call to parseAsonTag when it calls $(D resetForNextTag()).
  void resetForReuse() {
    depth = 0;
    line = 1;
  }

  /// Resets the tag state to get ready to parse the next tag.
  /// Should only be called by the parseAsonTag function.
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
  void setIsAnonymous()
  {
    this.name = anonymousTagNameIsNull ? null : "content";
  }
  void setName(inout(char)* start, inout(char)* limit)
  {
    //this.name = (start == limit) ? "content" : (cast(const(char)*)start)[0..limit-start];
    this.name = (start == limit) ? null : (cast(const(char)*)start)[0..limit-start];
  }
  bool isAnonymous() {
    return anonymousTagNameIsNull ? this.name is null : this.name == "content";
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
  ///          by itself but will not include the open brace if it has one.  Use toAson for that.
  string toString() {
    string str = "";
    if(namespace.length) {
      str ~= namespace;
      str ~= name;
    }
    if(!isAnonymous || (values.data.length == 0 && attributes.data.length == 0)) {
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
  void toAson(S, string indent = "    ")(S sink) if(isOutputRange!(S,const(char)[])) {
    //writefln("[DEBUG] converting to sdl namespace=%s name=%s values=%s attr=%s",
    //namespace, name, values.data, attributes.data);
    for(auto i = 0; i < depth; i++) {
      sink.put(indent);
    }
    if(namespace.length) {
      sink.put(namespace);
      sink.put(":");
    }
    if(!isAnonymous || (values.data.length == 0 && attributes.data.length == 0))
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
    throw new AsonParseException(line, format("unknown tag '%s'", name));
  }
  void throwIsDuplicate() {
    throw new AsonParseException(line, format("tag '%s' appeared more than once", name));
  }
  void getOneValue(T)(ref T value) {
    if(values.data.length != 1) {
      throw new AsonParseException
	(line,format("tag '%s' %s 1 value but had %s",
		     name, (values.data.length == 0) ? "must have at least" : "can only have", values.data.length));
    }

    const(char)[] literal = values.data[0];


    static if( isSomeString!T ) {

      if(!value.empty) throwIsDuplicate();

    } else static if( isIntegral!T || isFloatingPoint!T ) {

	//if( value != 0 ) throwIsDuplicate();

    } else {

    }

    if(!sdlLiteralToD!(T)(literal, value)) throw new AsonParseException(line, format("cannot convert '%s' to %s", literal, typeid(T)));
  }

  void getValues(T, bool allowAppend=false)(ref T[] t, size_t minCount = 1) {
    if(values.data.length < minCount) throw new AsonParseException(line, format("tag '%s' must have at least %s value(s)", name, minCount));

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
	if(literal[0] != '"') throw new AsonParseException(line, format("tag '%s' must have exactly one string literal but had another literal type", name));
	t[arrayOffset++] = literal[1..$-1]; // remove surrounding quotes
      } else {
	assert(0, format("Cannot convert sdl literal to D '%s' type", typeid(T)));
      }
    }
  }


  void enforceNoValues() {
    if(values.data.length) throw new AsonParseException(line, format("tag '%s' cannot have any values", name));
  }
  void enforceNoAttributes() {
    if(attributes.data.length) throw new AsonParseException(line, format("tag '%s' cannot have any attributes", name));
  }
  void enforceNoChildren() {
    if(hasOpenBrace) throw new AsonParseException(line, format("tag '%s' cannot have any children", name));
  }


}

version = use_lookup_tables;
/+
bool isIDStart(dchar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    /*
 The lookup table doesn't seem to be as fast here, maybe this case I should just compare the ranges
  version(use_lookup_tables) {
    return (c < sdlLookup.length) ? ((sdlLookup[c] & idStartFlag) != 0) : false;
  } else {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
  }
    */
}
bool isID(dchar c) {
  version(use_lookup_tables) {
    return (c < sdlLookup.length) ? ((sdlLookup[c] & sdlIDFlag) != 0) : false;
  } else {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '$';
  }
}
+/
enum tooManyCloseBraces = "too many ending braces '}'";
enum noEndingQuote = "string missing ending quote";
enum invalidBraceFmt = "found '{' on a different line than its tag '%s'.  fix the sdl by moving '{' to the same line";
enum mixedValuesAndAttributesFmt = "SDL values cannot appear after attributes, bring '%s' in front of the attributes for tag '%s'";
enum notEnoughCloseBracesFmt = "reached end of ASON but missing %s close brace(s) '}'";



/// Converts literal to the given D type T.
/// This is a wrapper arround the $(D sdlLiteralToD) function that returns true on sucess, except
/// this function returns the value itself and throws an AsonParseException on error.
T sdlLiteralToD(T)(const(char)[] literal) {
  T value;
  if(!sdlLiteralToD!(T)(literal, value))
    throw new AsonParseException(format("failed to convert '%s' to a %s", literal, typeid(T)));
  return value;
}

/// Converts literal to the given D type T.
/// If isSomeString!T, then it will remove the surrounding quotes if they are present.
/// Returns: true on succes, false on failure
bool sdlLiteralToD(T)(const(char)[] literal, ref T t) {

  assert(literal.length);


  static if( is( T == bool) ) {

    if(literal == "true" || literal == "on" || literal == "1") t = true;
    if(literal == "false" || literal == "off" || literal == "0") t = false;

  } else static if( isSomeString!T ) {

  if(literal[0] == '"' && literal.length > 1 && literal[$-1] == '"') {
    t = cast(T)literal[1..$-1];
  } else {
    t = cast(T)literal;
  }

  } else static if( isIntegral!T || isFloatingPoint!T ) {

    // remove any postfix characters
    while(true) {
      char c = literal[$-1];
      if(c >= '0' && c <= '9') break;
      literal.length--;
      if(literal.length == 0) return false;
    }

    t =  to!T(literal);

  } else {
      
    t = to!T(literal);

  }

  return true;
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




enum ubyte controlCharacter      = 0x01;
enum ubyte whitespace            = 0x02;
private __gshared ubyte[256] asonLookup =
  [
   ' ' : whitespace,
   '\t' : whitespace,
   '\n' : whitespace,
   '\v' : whitespace,
   '\f' : whitespace,
   '\r' : whitespace,

   '{' : controlCharacter,
   '}' : controlCharacter,
   '[' : controlCharacter,
   ']' : controlCharacter,
   '<' : controlCharacter,
   '>' : controlCharacter,
   ';' : controlCharacter,
   ',' : controlCharacter,
   '"' : controlCharacter,
   '\'' : controlCharacter,
   '\\' : controlCharacter,
   '#' : controlCharacter,
   '/' : controlCharacter,
   '*' : controlCharacter,
   //'=' : controlCharacter,
   ];
/+
version(use_lookup_tables) {
  mixin("private __gshared ubyte[256] asonLookup = "~rangeInitializers
	("'_'"    , "sdlIDFlag",

	 "'a'"    , "sdlIDFlag",
	 "'b'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'c'"    , "sdlIDFlag",
	 "'d'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'e'"    , "sdlIDFlag",
	 "'f'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'g'-'k'", "sdlIDFlag",
	 "'l'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'m'-'z'", "sdlIDFlag",

	 "'A'"    , "sdlIDFlag",
	 "'B'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'C'"    , "sdlIDFlag",
	 "'D'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'E'"    , "sdlIDFlag",
	 "'F'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'G'-'K'", "sdlIDFlag",
	 "'L'"    , "sdlIDFlag | sdlNumberFlag | sdlNumberPostfixFlag",
	 "'M'-'Z'", "sdlIDFlag",

	 "'0'-'9'", "sdlIDFlag | sdlNumberFlag",
	 "'-'"    , "sdlIDFlag",
	 "'.'"    , "sdlIDFlag | sdlNumberFlag",
	 "'$'"    , "sdlIDFlag",
	 )~";");
}
+/
/// A convenience function to parse a single tag.
/// Calls $(D tag.resetForReuse) and then calls $(D parseAsonTag).
/+
void parseOneAsonTag(Tag* tag, char[] sdlText) {
  tag.resetForReuse();
  if(!parseAsonTag(tag, &sdlText)) throw new AsonParseException(tag.line, format("The sdl text '%s' did not contain any tags", sdlText));
}
+/




struct AsonParser
{
  const char* start;
  const char* limit;

  this(char[] ason) {
    this.start = ason.ptr;
    this.limit = this.start + ason.length;
  }

  
}

version(unittest_ason) unittest
{
  AsonParser parser = AsonParser(setupAsonText("name Joe", false));

  
  


}





































struct AsonOptions
{
  ubyte flags;

  @property @safe bool preserveAsonText() pure nothrow const { return (flags & 1U) != 0;}
  @property @safe void perserveAsonText(bool v) pure nothrow { if (v) flags |= 1U;else flags &= ~1U;}

  @property @safe bool copyStrings() pure nothrow const { return (flags & 2U) != 0;}
  @property @safe void copyStrings(bool v) pure nothrow { if (v) flags |= 2U;else flags &= ~2U;}

  @property @safe bool asonIsList() pure nothrow const { return (flags & 128U) != 0;}
  @property @safe void asonIsList(bool v) pure nothrow { if (v) flags |= 128U;else flags &= ~128U;}
}






/+

void parseAsonInto(T)(AsonOptions options, string sdl)
{
  options.perserveAsonText = true;
  parseAsonInto(options, cast(char[])sdl);

}
void parseAsonInto(T)(AsonOptions options, char[] sdl)
{
  

 TAG_LOOP:
  while(walker.pop(depth)) {

    debug writefln("[DEBUG] parseAsonInto: at depth %s tag '%s'", tag.depth, tag.name);

    foreach(memberIndex, copyOfMember; obj.tupleof) {
    
      alias typeof(T.tupleof[memberIndex]) memberType;
      enum memberString = T.tupleof[memberIndex].stringof;

      //writefln("[DEBUG] tag '%s' checking member '%s %s'", tag.name, memberType.stringof, memberString);

      alias TypeTuple!(__traits(getAttributes, T.tupleof[memberIndex])) memberAttributes;
      alias ElementType!(memberType) memberElementType;
      enum isAppender = is( memberType == Appender!(AppenderElementType!(memberType)[]));

      static if(memberString == "this") {

	mixin(debugAsonReflection(T.stringof, memberString, "ignored because 'this' is always ignored"));
	
      } else static if(containsFlag!(AsonReflection.ignore, memberAttributes)) {

	mixin(debugAsonReflection(T.stringof, memberString, "ignored from AsonReflection.ignore"));

      } else static if( is( memberType == function) ) {

	mixin(debugAsonReflection(T.stringof, memberString, "ignored because it is a function"));

      } else static if( isAppender || ( !is( memberElementType == void ) && !isSomeString!(memberType) ) ) {


	static if(isAppender) {
	  mixin(debugAsonReflection(T.stringof, memberString, "deserialized as a list, specifically an appender"));

	  template addValues(string memberName) {
	    void addValues() {
	      auto elementOffset = __traits(getMember, obj, memberString).data.length;
	      __traits(getMember, obj, memberString).reserve(elementOffset + tag.values.data.length);
	      AppenderElementType!(memberType) deserializedValue;

	      foreach(value; tag.values.data) {
		if(!sdlLiteralToD!(AppenderElementType!(memberType))( value, deserializedValue)) {
		  throw new AsonParseException(tag.line, format("failed to convert '%s' to %s for appender %s.%s",
							       value, memberElementType.stringof, T.stringof, memberString) );
		}
		__traits(getMember, obj, memberString).put(deserializedValue);
		elementOffset++;
	      }
	    }
	  }

	} else {

	  mixin(debugAsonReflection(T.stringof, memberString, "deserialized as a list, specifically an array"));

	  template addValues(string memberName) {
	    void addValues() {
	      auto elementOffset = __traits(getMember, obj, memberString).length;

	      __traits(getMember, obj, memberString).length += tag.values.data.length;
	      foreach(value; tag.values.data) {
		if(!sdlLiteralToD!(memberElementType)( value, __traits(getMember, obj, memberString)[elementOffset] ) ) {
		  throw new AsonParseException(tag.line, format("failed to convert '%s' to %s for array member %s.%s",
							       value, memberElementType.stringof, T.stringof, memberString) );
		}
		elementOffset++;
	      }
	    }
	  }

	}

	static if(containsFlag!(AsonReflection.onlySingularTags, memberAttributes)) {
	  mixin(debugAsonReflection(T.stringof, memberString, format("onlySingularTags so will not handle tags named '%s'", memberString), true));
	} else {

	  if(tag.name == memberString) {

	    tag.enforceNoAttributes();

	    //
	    // Add tag values to the array
	    //
	    static if( !is( ElementType!(memberElementType) == void ) && !isSomeString!(memberElementType) ) {

	      implement("list of arrays");

	    } else static if( isAssociativeArray!(memberElementType)) {

	      implement("list of assoc-arrays");

	    } else static if( is ( isNested!( memberType ) ) ) {

	      implement("list of functions/structs/classes");

	    } else {

	      if(tag.values.data.length > 0) {
		addValues!(memberString);
	      }

	    }


	    if(tag.hasOpenBrace) {

	      size_t arrayDepth = tag.depth + 1;
	      while(walker.pop(arrayDepth)) {
		
		tag.enforceNoAttributes();
		// Check if the tag can be converted to an array element
		if(!tag.isAnonymous) {
		  throw new AsonParseException(tag.line, format("the child elements of array member %s.%s can only use anonymous tags, but found a tag with name '%s'",
							       T.stringof, memberString, tag.name));		  
		}
		
		
		static if( !isSomeString!(memberElementType) && isArray!(memberElementType)) {

		  implement("using children for list of arrays");

		} else static if( isAssociativeArray!(memberElementType)) {

		  implement("using children for list of assoc-arrays");

		} else static if( is ( isNested!(memberType) ) ) {

		  implement("using children for list of functions/structs/classes");

		} else {

		  if(tag.values.data.length > 0) {

		    addValues!(memberString);

		  }
		  
		}


	      }
	      
	    }

	    continue TAG_LOOP;
	  }
	}

	static if(containsFlag!(AsonReflection.noSingularTags, memberAttributes) ) {
	  mixin(debugAsonReflection(T.stringof, memberString, "does not handle singular tags", true));
	} else {
	  static if(singularName!(T, memberString) is null) {
	    static assert(0, format("Could not determine the singular name for %s.%s because it does not end with an 's'.  Use @(AsonSingularName(\"name\") to specify one.",
				    T.stringof, memberString));
	  }

	  mixin(debugAsonReflection(T.stringof, memberString, format("handles singular tags named '%s'", singularName!(T, memberString)), true));


	  if(tag.name == singularName!(T, memberString)) {

	    tag.enforceNoAttributes();
	    tag.enforceNoChildren();

	    static if( isArray!(memberElementType) &&
		       !isSomeString!(memberElementType) ) {

	      implement("singular list of arrays");

	    } else static if( isAssociativeArray!(memberElementType)) {

	      implement("singular list of assoc-arrays");

	    } else static if( is ( isNested!(memberType) ) ) {

	      implement("singular list of functions/structs/classes");

	    } else {

	      static if ( isAppender ) {
		AppenderElementType!(memberType) value;
	      } else {
		memberElementType value;
	      }

	      tag.getOneValue(value);
	      __traits(getMember, obj, memberString) ~= value;
	      debug writefln("[DEBUG] parseAsonInto: %s.%s was appended with '%s'", T.stringof, memberString, __traits(getMember, obj, memberString));
	      continue TAG_LOOP;
		    
	    }

	  }
	    
	}

	// END OF HANDLING OUTPUT RANGES

      } else static if( isAssociativeArray!(memberType)) {

	mixin(debugAsonReflection(T.stringof, memberString, "deserialized as an associative array"));
	implement("associative arrays");

      } else static if( is (isNested!(memberType))) {

	mixin(debugAsonReflection(T.stringof, memberString, "deserialized as an object"));
	implement("sub function/struct/class");

      } else {

	mixin(debugAsonReflection(T.stringof, memberString, "deserialized as a single value"));
	
	if(tag.name == memberString) {
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(__traits(getMember, obj, memberString));
	  debug writefln("[DEBUG] parseAsonInto: set %s.%s to '%s'", T.stringof, memberString, __traits(getMember, obj, memberString));
	  continue TAG_LOOP;
	}


      }

    }

    tag.throwIsUnknown();
  }

}



version(unittest_ason) unittest
{
  mixin(scopedTest!("AsonReflection"));

  void testParseType(T)(bool copyAson, string sdlText, T expectedType)
  {
    T parsedType;

    try {
      
      parseAsonInto!T(parsedType, setupAsonText(sdlText, copyAson));

    } catch(Exception e) {
      writefln("the following sdl threw an unexpected exception: %s", sdlText);
      writeln(e);
      assert(0);
    }

    stdout.flush();
    if(expectedType != parsedType) {
      writefln("Expected: %s", expectedType);
      writefln(" but got: %s", parsedType);
      assert(0);
    }

  }

  struct TypeWithAppender
  {
    auto values = appender!(int[])();
    this(int[] values...) {
      foreach(value; values) {
	this.values.put(value);
      }
    }
  }
  testParseType(false,`
values 1 2 3
values {
    4 5 6 7
    8 9 10 11
}
value 12
value 13
`, TypeWithAppender(1,2,3,4,5,6,7,8,9,10,11,12,13));

  struct PackageInfo
  {
    @(AsonReflection.ignore)
    string ignoreThisMember;

    string name;
    private string privateName;
    uint packageID;

    uint[] randomUints;

    string[] authors;

    @(AsonReflection.noSingularTags)
    string[] sourceFiles;

        
    @(AsonSingularName("dependency"))
    string[string][] dependencies;

    @(AsonReflection.onlySingularTags)
    @(AsonSingularName("a-float"))
    float[] myFloats;
        


    void reset() {
      name = null;
      packageID = 0;
      randomUints = null;
      authors = null;
      sourceFiles = null;
      dependencies = null;
    }
  }



  testParseType(false, `
name "vibe-d"
privateName "secret"
packageID 1023
randomUints 1 2 3 4
`, PackageInfo(null, "vibe-d", "secret", 1023, [1,2,3,4]));

  testParseType(false, `
randomUint 1
randomUints 2 3 4 5
randomUints {
  99 8291 
  83992
}
randomUint 9983`, PackageInfo(null, null, null, 0, [1,2,3,4,5,99,8291,83992,9983]));

  testParseType(false, `
authors "Jimbo"
authors "Spencer" "Dylan"
authors {
    "Jay"
    "Amy" "Steven"
}
author "SingleAuthor"
`, PackageInfo(null, null, null, 0, null, ["Jimbo", "Spencer", "Dylan", "Jay", "Amy", "Steven", "SingleAuthor"]));


  testParseType(false,`
a-float 0
// a-float 1 2     # should be an error
// a-float         # should be an error
// myFloats 1 2 3  # should be an error
a-float 2.3829
a-float -192
`, PackageInfo(null, null, null, 0, null, null, null, null, [0, 2.3829, -192]));




}

+/































void parseAson(AsonOptions options, string sdl)
{
  options.perserveAsonText = true;
  parseAson(options, cast(char[])sdl);
}


/// Parses one SDL tag (not including its children) from sdlText saving slices for every
/// name/value/attribute to the given tag struct.
/// This function assumes that sdlText contains at least one full SDL _tag.
/// The only time this function will allocate memory is if the value/attribute appenders
/// in the tag struct are not large enough to hold all the values.
/// Because of this, after the tag values/attributes are populated, it is up to the caller to copy
/// any memory they wish to save unless sdlText is going to persist in memory.
/// Note: this function does not handle the UTF-8 bom because it doesn't make sense to re-check
///       for the BOM after every tag.
/// Params:
///   tag = An address to a Tag structure to save the sdl information.
///   sdlText = An address to the sdl text character array.
///             the function will move the front of the slice foward past
///             any sdl that was parsed.
/// Returns: true if a tag was found, false otherwise
/// Throws: AsonParseException or Utf8Exception
void parseAson(AsonOptions options, char[] sdlText)
{
  size_t line = 1;

  // developer note:
  //   whenever reading the next character, the next pointer must be saved to cpos
  //   if the character could be used later, but if the next is guaranteed to
  //   be thrown away (such as when skipping till the next newline after a comment)
  //   then cpos does not need to be saved.

  char *next = sdlText.ptr;
  char *limit = next + sdlText.length;

  size_t depth = 0;

  //options.startParser(); // Start the parse

  char* cpos;
  dchar c;

  char[] token;

  void enforceNoMoreObjects() {
    if(depth > 0) throw new AsonParseException(line, format(notEnoughCloseBracesFmt, depth));
  }

  void readNext()
  {
    cpos = next;
    c = decodeUtf8(next, limit);
  }

  bool isWhitespaceOrControl()
  {
    return c < asonLookup.length && ( ( (asonLookup[c] & whitespace      ) != 0) ||
                                      ( (asonLookup[c] & controlCharacter) != 0) );
  }


  // Expected State:
  //   next: points to the next character (could be the newline)
  // Return State:
  //   next: points to the next character after the newline, or at limit
  void toNextLine()
  {
    while(true) {
      if(next >= limit) { return; }
      c = decodeUtf8(next, limit); // no need to save cpos since c will be thrown away
      if(c == '\n') { line++; return; }
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

	line++;

      } else if(c == '#') {

	toNextLine();

      } else if(c == '/') {

	if(next >= limit) return;

	dchar secondChar = decodeUtf8(next, limit);

	if(secondChar == '/') {

	  toNextLine();

	} else if(secondChar == '*') {

	  
	MULTILINE_COMMENT_LOOP:
	  while(next < limit) {

	    c = decodeUtf8(next, limit); // no need to save cpos since c will be thrown away
	    if(c == '\n') {
	      line++;
	    } else if(c == '*') {
	      // loop assume c is pointing to a '*' and next is pointing to the next characer
	      while(next < limit) {

		c = decodeUtf8(next, limit);
		if(c == '/') break MULTILINE_COMMENT_LOOP;
		if(c == '\n') {
		  line++;
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

	return;

      }

      // Goto next character
      if(next >= limit) {cpos = next; break;}
      readNext();
    }

    return;
  }


  // Expectd State:
  //   c/cpos: the first character of a name
  // Return State:
  //   c/cpos: the first non-whitespace character after the name
  //   token: contains the name
  void parseName()
  {
    auto startOfString = cpos;

    if(c == '\'') {
      implement("single-quoted strings");
    } else if(c == '"') {
      implement("double-quoted strings");
    } else {

      while(true) {
	if(next >= limit) {
	  cpos = next;
	  break;
	}
	c = decodeUtf8(next, limit);
	if(isWhitespaceOrControl()) break;
      }

      token = startOfString[0..cpos-startOfString];

    }
  }


  // Expectd State:
  //   c/cpos: the first character of a name
  //   next: points to character after cpos
  // Return State:
  //   c/cpos: the first non-whitespace character after the name-value section
  void parseNameValues()
  {
    parseName();
  }


  if(next >= limit) return;
  readNext();
  skipWhitespaceAndComments();
  if(cpos >= limit) return;

  if(options.asonIsList) {

    implement("ason root level list");

  } else {
      
    // Skip optional open brace
    if(c == '{') {
      if(next >= limit) return; // TODO: should this be an error?
      readNext();
      skipWhitespaceAndComments();
    }
    
    parseNameValues();

    if(cpos >= limit) return; // TODO: should this be an error?

    // Skip optional end brace
    if(c == '}') {
      if(next >= limit) return; // TODO: should this be an error if no open brace was specified?
      skipWhitespaceAndComments();
    }

    if(cpos < limit) throw new AsonParseException(line, "expected end of input but found '%s'", cpos[0]);
  }

}

version(unittest_ason)
{
  char[2048] asonBuffer;
  char[asonBuffer.length] asonBuffer2;
  char[] setupAsonText(const(char[]) asonText, bool copyAson)
  {
    if(!copyAson) return cast(char[])asonText;

    if(asonText.length >= asonBuffer.length) throw new Exception(format("attempting to copy ason of length %s but asonBuffer is only of length %s", asonText.length, asonBuffer.length));
    asonBuffer[0..asonText.length] = asonText;
    return asonBuffer[0..asonText.length];
  }

  struct AsonBuffer2Sink
  {
    size_t offset;
    @property
    char[] slice() { return asonBuffer2[0..offset]; }
    void put(inout(char)[] value) {
      asonBuffer2[offset..offset+value.length] = value;
      offset += value.length;
    }
  }

}

version(unittest_ason) unittest
{
  AsonOptions options;

  void testParseAson(bool reparse = true)(bool copyAson, const(char)[] asonText, /*Ason expectedAson, */size_t line = __LINE__)
  {
    auto escapedAsonText = escape(asonText);

    debug {
      static if(reparse) {
	writefln("[TEST] testing ason              '%s'", escapedAsonText);
      } else {
	writefln("[TEST] testing ason (regenerated)'%s'", escapedAsonText);
      }
    }

    char[] next = setupAsonText(asonText, copyAson);

    //parsedTag.resetForNewAson();


    try {

      parseAson(options, next);
/+
      // put the tag into the buffer2 sink to reparse again after
      static if(reparse) {
	parsedTag.toAson(&buffer2Sink);
	previousDepth = parsedTag.depth;
	if(parsedTag.hasOpenBrace) previousDepth++;
      }

      if(parseAsonTag(&parsedTag, &next)) {
	writefln("Expected %s tag(s) but got at least one more (depth=%s, name='%s')",
		 expectedTags.length, parsedTag.depth, parsedTag.name);
	writefln("Error: test on line %s", line);
	assert(0);
      }
+/      
    } catch(AsonParseException e) {
      writefln("[TEST] this ason threw an unexpected AsonParseException: '%s'", escape(asonText));
      writeln(e);
      writefln("Error: test on line %s", line);
      assert(0);
    } catch(Exception e) {
      writefln("[TEST] this ason threw an unexpected Exception: '%s'", escape(asonText));
      writeln(e);
      writefln("Error: test on line %s", line);
      assert(0);
    }
/+
    static if(reparse) {
      if(previousDepth != size_t.max) {
	while(previousDepth > parsedTag.depth) {
	  buffer2Sink.put("}");
	  previousDepth--;
	}
      }

      if(buffer2Sink.slice != asonText &&
	 (buffer2Sink.slice.length && buffer2Sink.slice[0..$-1] != asonText)) {
	testParseAson!false(false, buffer2Sink.slice, expectedTags, line);
      }
    }
+/
  }

  testParseAson(false, "name Johnny");
  testParseAson(false, "{\"name\":\"Johnny\"}");
  testParseAson(false, "{name:\"Johnny\"}");
  testParseAson(false, "{name:Johnny}");
  testParseAson(false, "{name Johnny}");
}





/+

version(unittest_ason) unittest
{
  //return; // Uncomment to disable these tests

  mixin(scopedTest!"AsonParse");

  Tag parsedTag;

  void useProposed() {
    debug writefln("[TEST] AsonMode: Proposed");
    parsedTag.useProposedAson();
  }
  void useStrict() {
    debug writefln("[TEST] AsonMode: Strict");
    parsedTag.useStrictAson();
  }


  struct AsonTest
  {
    bool copyAson;
    string sdlText;
    Tag[] expectedTags;
    this(bool copyAson, string sdlText, Tag[] expectedTags...) {
      this.copyAson = copyAson;
      this.sdlText = sdlText;
      this.expectedTags = expectedTags;
    }
  }

  void testParseAson(bool reparse = true)(bool copyAson, const(char)[] sdlText, Tag[] expectedTags...)
  {
    size_t previousDepth = size_t.max;
    AsonBuffer2Sink buffer2Sink;

    auto escapedAsonText = escape(sdlText);

    debug {
      static if(reparse) {
	writefln("[TEST] testing sdl              : %s", escapedAsonText);
      } else {
	writefln("[TEST] testing sdl (regenerated): %s", escapedAsonText);
      }
    }

    char[] next = setupAsonText(sdlText, copyAson);

    parsedTag.resetForReuse();


    try {

      for(auto i = 0; i < expectedTags.length; i++) {
	if(!parseAsonTag(&parsedTag, &next)) {
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
	  parsedTag.toAson(&buffer2Sink);
	  previousDepth = parsedTag.depth;
	  if(parsedTag.hasOpenBrace) previousDepth++;
	}
      }

      if(parseAsonTag(&parsedTag, &next)) {
	writefln("Expected %s tag(s) but got at least one more (depth=%s, name='%s')",
		 expectedTags.length, parsedTag.depth, parsedTag.name);
	assert(0);
      }
      
    } catch(AsonParseException e) {
      writefln("[TEST] this sdl threw an unexpected AsonParseException: '%s'", escape(sdlText));
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
	testParseAson!false(false, buffer2Sink.slice, expectedTags);
      }
    }

  }

  void testInvalidAson(bool copyAson, const(char)[] sdlText, AsonErrorType expectedErrorType = AsonErrorType.unknown) {
    auto escapedAsonText = escape(sdlText);
    debug writefln("[TEST] testing invalid sdl '%s'", escapedAsonText);

    AsonErrorType actualErrorType = AsonErrorType.unknown;

    char[] next = setupAsonText(sdlText, copyAson);

    parsedTag.resetForReuse();
    try {
      while(parseAsonTag(&parsedTag, &next)) { }
      writefln("Error: invalid sdl was successfully parsed: %s", sdlText);
      assert(0);
    } catch(AsonParseException e) {
      debug writefln("[TEST]    got expected error: %s", e.msg);
      actualErrorType = e.type;
    } catch(Utf8Exception e) {
      debug writefln("[TEST]    got expected error: %s", e.msg);
    }

    if(expectedErrorType != AsonErrorType.unknown &&
       expectedErrorType != actualErrorType) {
      writefln("expected error '%s' but got error '%s'", expectedErrorType, actualErrorType);
      assert(0);
    }

  }

  testParseAson(false, "");
  testParseAson(false, "  ");
  testParseAson(false, "\n");

  testParseAson(false, "#Comment");
  testParseAson(false, "#Comment copyright \u00a8");
  testParseAson(false, "#Comment\n");
  testParseAson(false, "#Comment\r\n");
  testParseAson(false, "  #   Comment\r\n");

  testParseAson(false, "  --   Comment\n");
  testParseAson(false, " ------   Comment\n");

  testParseAson(false, "  #   Comment1 \r\n  -- Comment 2");


  testParseAson(false, " //   Comment\n");
  testParseAson(false, " ////   Comment\n");

  testParseAson(false, "/* a multiline comment \n\r\n\n\n\t hello stuff # -- // */");

  // TODO: test this using the allowBracesAfterNewline option
  //  testParseAson(false, "tag /*\n\n*/{ child }", Tag("tag"), Tag("child"));


  testParseAson(false, "a", Tag("a"));
  testParseAson(false, "ab", Tag("ab"));
  testParseAson(false, "abc", Tag("abc"));
  testParseAson(false, "firsttag", Tag("firsttag"));
  testParseAson(false, "funky._-$tag", Tag("funky._-$tag"));


  {
    auto prefixes = ["", " ", "\t", "--comment\n"];
    foreach(prefix; prefixes) {
      testInvalidAson(false, prefix~":");
    }
  }

  auto namespaces = ["a:", "ab:", "abc:"];
  bool isProposedAson = false;
  while(true) {
    string tagName;
    if(isProposedAson) {
      tagName = null;
      useProposed();
    } else {
      tagName = "content";
    }
    foreach(namespace; namespaces) {
      testParseAson(false, namespace, Tag(namespace~tagName));
      testParseAson(false, namespace~" ", Tag(namespace~tagName));
      testParseAson(false, namespace~"\t", Tag(namespace~tagName));
      testParseAson(false, namespace~"\n", Tag(namespace~tagName));
      testParseAson(false, namespace~";", Tag(namespace~tagName));
      testParseAson(false, namespace~`"value"`, Tag(namespace~tagName, `"value"`));
      //testParseAson(false, namespace~`attr=null`, Tag(namespace~tagName, "attr=null"));
    }
    if(isProposedAson) break;
    isProposedAson = true;
  }
  useStrict();


  testParseAson(false, "a:a", Tag("a:a"));
  testParseAson(false, "ab:a", Tag("ab:a"));

  testParseAson(false, "a:ab", Tag("a:ab"));
  testParseAson(false, "ab:ab", Tag("ab:ab"));

  testParseAson(false, "html:table", Tag("html:table"));

  testParseAson(false, ";", Tag("content"));
  testParseAson(false, "myid;", Tag("myid"));
  testParseAson(false, "myid;   ", Tag("myid"));
  testParseAson(false, "myid #comment", Tag("myid"));
  testParseAson(false, "myid # comment \n", Tag("myid"));
  testParseAson(false, "myid -- comment \n # more comments\n", Tag("myid"));


  testParseAson(false, "myid /* multiline comment */", Tag("myid"));
  testParseAson(false, "myid /* multiline comment */ ", Tag("myid"));
  testParseAson(false, "myid /* multiline comment */\n", Tag("myid"));
  testParseAson(false, "myid /* multiline comment \n\n */", Tag("myid"));
  testParseAson(false, "myid /* multiline comment **/ \"value\"", Tag("myid", `"value"`));
  testParseAson(false, "myid /* multiline comment \n\n */another-id", Tag("myid"), Tag("another-id"));
  testParseAson(false, "myid /* multiline comment */ \"value\"", Tag("myid", `"value"`));
  testParseAson(false, "myid /* multiline comment \n */ \"value\"", Tag("myid"), Tag("content", `"value"`));
  testInvalidAson(false, "myid /* multiline comment \n */ { \n }");
  useProposed();
  testParseAson(false, "myid /* multiline comment */ { \n }", Tag("myid"));
  testParseAson(false, "myid /* multiline comment \n */ \"value\"", Tag("myid"), Tag(null, `"value"`));
  useStrict();


  testParseAson(false, "tag1\ntag2", Tag("tag1"), Tag("tag2"));
  testParseAson(false, "tag1;tag2\ntag3", Tag("tag1"), Tag("tag2"), Tag("tag3"));

  testInvalidAson(false, "myid {");
  testInvalidAson(false, "myid {\n\n");

  testInvalidAson(false, "{}");

  testParseAson(false, "tag1{}", Tag("tag1"));
  testParseAson(false, "tag1{}tag2", Tag("tag1"), Tag("tag2"));
  testParseAson(false, "tag1{}\ntag2", Tag("tag1"), Tag("tag2"));

  testParseAson(false, "tag1{tag1.1}tag2", Tag("tag1"), Tag("tag1.1"), Tag("tag2"));

  testParseAson(false, `tag"value"`, Tag("tag", `"value"`));


  //
  // Handling the backslash '\' character
  //
  testInvalidAson(false, "\\"); // slash must in the context of a tag
  testInvalidAson(false, `tag \ x`);

  testParseAson(false, "tag\\", Tag("tag")); // Make sure this is valid sdl
  testParseAson(false, "tag \\  \n \\ \n \"hello\"", Tag("tag", `"hello"`));

  //
  // Test the keywords (white box tests trying to attain full code coverage)
  //
  auto keywords = ["null", "true", "false", "on", "off"];

  foreach(keyword; keywords) {
    testParseAson(false, keyword, Tag("content", keyword));
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
	testInvalidAson(false, sdlBuffer[0..afterTagName+cutoff]);
      }
    }
    auto suffixes = [";", " \t;", "\n", "{}", " \t {\n }"];
    foreach(keyword; keywords) {
      auto limit = afterTagName+keyword.length;

      sdlBuffer[afterTagName..limit] = keyword;
      testParseAson(false, sdlBuffer[0..limit], Tag(expectedTagName, keyword));

      foreach(suffix; suffixes) {
	sdlBuffer[limit..limit+suffix.length] = suffix;
	testParseAson(false, sdlBuffer[0..limit+suffix.length], Tag(expectedTagName, keyword));
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
	  testParseAson(false, sdlBuffer[0..limit+8], Tag(expectedTagName, format(`%s%s="value"`, attrNamespace, keyword[0..cutoff])));

	  foreach(otherKeyword; keywords) {
	    sdlBuffer[limit+1..limit+1+otherKeyword.length] = otherKeyword;
	    testParseAson(false, sdlBuffer[0..limit+1+otherKeyword.length],
			 Tag(expectedTagName, format("%s%s=%s", attrNamespace, keyword[0..cutoff], otherKeyword)));
	  }
	}

      }

    }
  }

  


  //
  // String Literals
  //
  testParseAson(false, `a "apple"`, Tag("a", `"apple"`));
  testParseAson(false, "a \"pear\"\n", Tag("a", `"pear"`));
  testParseAson(false, "a \"left\"\nb \"right\"", Tag("a", `"left"`), Tag("b", `"right"`));
  testParseAson(false, "a \"cat\"\"dog\"\"bear\"\n", Tag("a", `"cat"`, `"dog"`, `"bear"`));
  testParseAson(false, "a \"tree\";b \"truck\"\n", Tag("a", `"tree"`), Tag("b", `"truck"`));

  //
  // Attributes
  //
  testParseAson(false, "tag attr=null", Tag("tag", "attr=null"));
  testParseAson(false, "tag \"val\" attr=null", Tag("tag", `"val"`, "attr=null"));

  auto mixedValuesAndAttributesTests = [
    AsonTest(false, "tag attr=null \"val\"", Tag("tag", "attr=null", `"val"`)) ];

  foreach(test; mixedValuesAndAttributesTests) {
    testInvalidAson(test.copyAson, test.sdlText, AsonErrorType.mixedValuesAndAttributes);
  }
  useProposed();
  foreach(test; mixedValuesAndAttributesTests) {
    testParseAson(test.copyAson, test.sdlText, test.expectedTags);
  }
  useStrict();

  //
  // Test parsing numbers without extracting them
  //
  enum numberPostfixes = ["", "l", "L", "f", "F", "d", "D", "bd", "BD"];
  {
    enum sdlPostfixes = ["", " ", ";", "\n"];
    
    auto numbers = ["0", "12", "9876", "5432", /*".1",*/ "0.1", "12.4", /*"1.",*/ "8.04",  "123.l"];


    for(size_t negative = 0; negative < 2; negative++) {
      string prefix = negative ? "-" : "";

      foreach(postfix; numberPostfixes) {
	foreach(number; numbers) {

	  auto testNumber = prefix~number~postfix;

	  if(postfix.length) {
	    useProposed();
	    testInvalidAson(false, "tag "~testNumber);
	    useStrict();
	  }
	  //testInvalidAson(false, "tag "~testNumber~"=");

	  foreach(sdlPostfix; sdlPostfixes) {
	    testParseAson(false, "tag "~testNumber~sdlPostfix, Tag("tag", testNumber));
	  }
	}
      }

      
    }
  }
  
  //
  // Test parsing numbers and extracting them
  //
  {
    for(size_t negative = 0; negative < 2; negative++) {
      string prefix = negative ? "-" : "";

      foreach(postfix; numberPostfixes) {

	void testNumber(Types...)(ulong expectedValue) {
	  long expectedSignedValue = negative ? -1 * (cast(long)expectedValue) : cast(long)expectedValue;

	  foreach(Type; Types) {
	    if(negative && isUnsigned!Type) continue;
	    if(expectedSignedValue > Type.max) continue;
	    static if( is(Type == float) || is(Type == double) || is(Type == real)) {
	      if(expectedSignedValue < Type.min_normal) continue;
	    } else {
	      if(expectedSignedValue < Type.min) continue;
	    }	       

	    debug writefln("[DEBUG] testing %s on %s", typeid(Type), parsedTag.values.data[0]);
	    Type t;
	    parsedTag.getOneValue(t);
	    assert(t == cast(Type) expectedSignedValue, format("Expected (%s) %s but got %s", typeid(Type), expectedSignedValue, t));
	  }
	}
	void testDecimalNumber(Types...)(real expectedValue) {
	  foreach(Type; Types) {
	    if(negative && isUnsigned!Type) continue;
	    if(expectedValue > Type.max) continue;
	    static if( is(Type == float) || is(Type == double) || is(Type == real)) {
	      if(expectedValue < Type.min_normal) continue;
	    } else {
	      if(expectedValue < Type.min) continue;
	    }	       

	    debug writefln("[DEBUG] testing %s on %s", typeid(Type), parsedTag.values.data[0]);
	    Type t;
	    parsedTag.getOneValue(t);
	    assert(t - cast(Type) expectedValue < .01, format("Expected (%s) %s but got %s", typeid(Type), cast(Type)expectedValue, t));
	  }
	}

	alias testNumber!(byte,ubyte,short,ushort,int,uint,long,ulong,float,double,real) testNumberOnAllTypes;
	alias testDecimalNumber!(float,double,real) testDecimalNumberOnAllTypes;
	
	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"0"~postfix);
	testNumberOnAllTypes(0);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"1"~postfix);
	testNumberOnAllTypes(1);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"12"~postfix);
	testNumberOnAllTypes(12);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"9987"~postfix);
	testNumberOnAllTypes(9987);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"0.0"~postfix);
	testDecimalNumberOnAllTypes(0.0);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~".1"~postfix);
	testDecimalNumberOnAllTypes(0.1);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~".000001"~postfix);
	testDecimalNumberOnAllTypes(0.000001);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"100384.999"~postfix);
	testDecimalNumberOnAllTypes(100384.999);

	parseOneAsonTag(&parsedTag, cast(char[])"tag "~prefix~"3.14159265"~postfix);
	testDecimalNumberOnAllTypes(3.14159265);
      }	
    }

  }


  //
  // Children
  //
  testInvalidAson(false, "{}"); // no line can start with a curly brace

  auto braceAfterNewlineTests = [
    AsonTest(false, "tag\n{  child\n}", Tag("tag"), Tag("child")),
    AsonTest(false, "colors \"hot\" \n{  yellow\n}", Tag("colors", `"hot"`), Tag("yellow")) ];

  foreach(test; braceAfterNewlineTests) {
    testInvalidAson(test.copyAson, test.sdlText, AsonErrorType.braceAfterNewline);
  }
  useProposed();
  foreach(test; braceAfterNewlineTests) {
    testParseAson(test.copyAson, test.sdlText, test.expectedTags);
  }
  useStrict();

  //
  // Odd corner cases for this implementation
  //
  testParseAson(false, "tag null;", Tag("tag", "null"));
  testParseAson(false, "tag null{}", Tag("tag", "null"));
  testParseAson(false, "tag true;", Tag("tag", "null"));
  testParseAson(false, "tag true{}", Tag("tag", "null"));
  testParseAson(false, "tag false;", Tag("tag", "null"));
  testParseAson(false, "tag false{}", Tag("tag", "null"));


  // TODO: testing using all keywords as namespaces true:id, etc.
  testParseAson(false, "tag null:null=\"value\";", Tag("tag", "null:null=\"value\""));
  testParseAson(false, "null", Tag("content", "null"));



  //
  // Full Parses
  //
  testParseAson(false, `
name "joe"
children {
  name "jim"
}`, Tag("name", `"joe"`), Tag("children"), Tag("name", `"jim"`));

  testParseAson(false, `
parent name="jim" {
  child "hasToys" name="joey" {
     # just a comment here for now
  }
}`, Tag("parent", "name=\"jim\""), Tag("child", "name=\"joey\"", `"hasToys"`));


  testParseAson(false,`html:table {
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
+/

/// Assists in walking an SDL tree which supports the StAX method of parsing.
/// Examples:
/// ---
/// Tag tag;
/// AsonWalker walker = AsonWalker(&tag, sdl);
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
/+
struct AsonWalker
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
	return true;
      }
    }

    while(true) {
      size_t previousDepth;
      const(char)[] previousName;

      if(!allowSkipChildren) {
	previousDepth = tag.depth;
	previousName = tag.name;
      }

      if(!parseAsonTag(this.tag, &sdl)) {
	assert(tag.depth == 0, format("code bug: parseAsonTag returned end of input but tag.depth was %s (not 0)", tag.depth));
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


}
+/

/+
void parseAson(T, bool ignoreUnknown = false)(T t, inout(char)[] sdl) {
  inout(char)* start = sdl.ptr;
  inout(char)* limit = start + sdl.length;
  parseAson!(T)(t, start, limit);
}
void parseAson(T, bool ignoreUnknown = false)(ref T t, const(char)* start, const char* limit)  {
  Tag tag;

  writefln("Parsing sdl struct with the following members:");
  foreach(member; __traits(allMembers, T)) {
    writefln("  %s", member);
  }


 TAG_LOOP:
  while(parseAsonTag(&tag, start, limit)) {

    writefln("parseAson: (depth %s) tag '%s'%s", tag.depth, tag.name,
	     tag.hasOpenBrace ? " (has children)" : "");


    foreach(member; __traits(allMembers, T)) {
      if(tag.name == member) {
	writefln("matched member '%s'", member);
	continue TAG_LOOP;
      }
    }

    static if(ignoreUnknown) {
      writefln("parseAson: error: no match for tag '%s'", tag.name);
    } else {
      throw new AsonParseException(tag.line, format("unknown tag '%s'", tag.name));
    }

  }

}
+/
/+
version(unittest_ason)
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
    void parseAsonPackage(bool copyAson, string sdlText) {
      parseAsonPackage(setupAsonText(sdlText, copyAson));
    }
    void parseAsonPackage(char[] sdlText) {
      Tag tag;
      auto sdl = AsonWalker(&tag, sdlText);
      while(sdl.pop()) {

	debug writefln("[sdl] (depth %s) tag '%s'%s", tag.depth, tag.name,
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
+/

version(unittest_ason) unittest
{
/+
  mixin(scopedTest!"AsonWalker");

  void testPackage(bool copyAson, string sdlText, ref Package expectedPackage)
  {
    Package parsedPackage;

    parsedPackage.parseAsonPackage(copyAson, sdlText);

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

+/
}


version(unittest_ason) unittest
{
/+
  mixin(scopedTest!"AsonWalkerOnPerson");

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
    void parseFromAson(ref AsonWalker walker) {
      auto tag = walker.tag;

      tag.enforceNoValues();
      tag.enforceNoAttributes();

      reset();

      auto childBuilder = appender!(Person[])();

      auto depth = walker.childrenDepth();
      while(walker.pop(depth)) {

	//writefln("[sdl] (depth %s) tag '%s'%s", tag.depth, tag.name,
	//tag.hasOpenBrace ? "(has children)" : "");
	//stdout.flush();

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
	  child.parseFromAson(walker);
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
    auto walker = AsonWalker(&tag, sdl);
    while(walker.pop()) {
      if(tag.name == "person") {

	person.parseFromAson(walker);
	people.put(person);

      } else tag.throwIsUnknown();
    }

    return people;
  }

  void testParsePeople(bool copyAson, string sdlText, Person[] expectedPeople...)
  {
    Appender!(Person[]) parsedPeople;
    try {

      parsedPeople = parsePeople(setupAsonText(sdlText, copyAson));

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
    child {
        name "Sally"
        age 8
    }
}`, Person("Robert", 29, ["Bob", "Bobby"], [Person("Jack", 6, ["Little Jack"]),Person("Sally", 8)]));

+/

}

