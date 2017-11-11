/**
   $(P An SDL ($(LINK2 http://www.ikayzo.org/display/SDL/Home,Simple Declarative Language)) parser.
     Supports StAX/SAX style API. See $(D more.std.dom) for DOM style API.)

   Examples:
   --------------------------------
   void printTags(char[] sdl) {
       Tag tag;
       while(parseSdlTag(&tag, &sdl)) {
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
   TODO: implement escaped strings
   TODO: finish unit tests
   TODO: write a input-range sdl parser
   TODO: implement datetime/timespans

   Authors: Jonathan Marler, johnnymarler@gmail.com
   License: use freely for any purpose
 */

module more.sdl;

import core.stdc.string : memmove;

import std.array;
import std.string;
import std.range;
import std.conv;
import std.bitmanip;
import std.traits;

import more.common;
import more.utf8;

version(unittest_sdl)
{
  import std.stdio;
}

alias LineNumber = size_t;

/// Used in SdlParseException to distinguish specific sdl parse errors.
enum SdlErrorType {
  unknown,
  braceAfterNewline,
  mixedValuesAndAttributes,
}
/// Thrown by sdl parse functions when invalid SDL is encountered.
class SdlParseException : Exception
{
  SdlErrorType type;
  LineNumber lineInSdl;
  this(LineNumber lineInSdl, string msg, string file = __FILE__, size_t codeLine = __LINE__) {
    this(SdlErrorType.unknown, lineInSdl, msg, file, codeLine);
  }
  this(SdlErrorType errorType, LineNumber lineInSdl, string msg, string file = __FILE__, size_t codeLine = __LINE__) {
    super((lineInSdl == 0) ? msg : "line "~to!string(lineInSdl)~": "~msg, file, codeLine);
    this.type = errorType;
    this.lineInSdl = lineInSdl;
  }
}

/// Holds three character arrays for an SDL attribute, namespace/id/value.
struct Attribute {
  //size_t line, column;
  const(char)[] namespace;
  const(char)[] id;
  const(char)[] value;
}

/// Contains a tag's name, values and attributes.
/// It does not contain any information about its child tags because that part of the sdl would not have been parsed yet, however,
/// it does indicate if the tag was followed by an open brace.
/// This struct is used directly for the StAX/SAX APIs and indirectly for the DOM or Reflection APIs.
struct Tag {

  // A bifield of flags used to pass extra options to parseSdlTag.
  // Used to accept/reject different types of SDL or cause parseSdlTag to
  // behave differently like preventing it from modifying the sdl text.
  private ubyte flags;

  /// Normally SDL only allows a tag's attributes to appear after all it's values.
  /// This flag causes parseSdlTag to allow values/attributes to appear in any order, i.e.
  ///     $(D tag attr="my-value" "another-value" # would be valid)
  @property @safe bool allowMixedValuesAndAttributes() pure nothrow const { return (flags & 1U) != 0;}
  @property @safe void allowMixedValuesAndAttributes(bool v) pure nothrow { if (v) flags |= 1U;else flags &= ~1U;}

  /// Causes parseSdlTag to allow a tag's open brace to appear after any number of newlines
  @property @safe bool allowBraceAfterNewline() pure nothrow const        { return (flags & 2U) != 0;}
  @property @safe void allowBraceAfterNewline(bool v) pure nothrow        { if (v) flags |= 2U;else flags &= ~2U;}

  /// Causes parseSdlTag to allow a child tags to appear on the same line as the parents
  /// open and close braces
  @property @safe bool allowChildTagsOnSameLineAsBrace() pure nothrow const { return (flags & 4U) != 0;}
  @property @safe void allowChildTagsOnSameLineAsBrace(bool v) pure nothrow { if (v) flags |= 4U;else flags &= ~4U;}

  // Causes parseSdlTag to throw an exception if it finds any number literals
  // with postfix letters indicating the type
  // @property @safe bool verifyTypedNumbers() pure nothrow const            { return (flags & 4U) != 0;}
  // @property @safe void verifyTypedNumbers(bool v) pure nothrow            { if (v) flags |= 4U;else flags &= ~4U;}

  /// Causes parseSdlTag to set the tag name to null instead of "content" for anonymous tags.
  /// This allows the application to differentiate betweeen "content" tags and anonymous tags.
  @property @safe bool anonymousTagNameIsNull() pure nothrow const        { return (flags & 8U) != 0;}
  @property @safe void anonymousTagNameIsNull(bool v) pure nothrow        { if (v) flags |= 8U;else flags &= ~8U;}

  /// Causes parseSdlTag to accept non-quoted strings
  @property @safe bool acceptUnquotedStrings() pure nothrow const        { return (flags & 16U) != 0;}
  @property @safe void acceptUnquotedStrings(bool v) pure nothrow        { if (v) flags |= 16U;else flags &= ~16U;}

  /// Prevents parseSdlTag from modifying the given sdl text for things such as
  /// processing escaped strings
  @property @safe bool preserveSdlText() pure nothrow const               { return (flags & 128U) != 0;}
  @property @safe void preserveSdlText(bool v) pure nothrow               { if (v) flags |= 128U;else flags &= ~128U;}


  // TODO: maybe add an option to specify that any values accessed should be copied to new buffers
  // NOTE: Do not add an option to prevent parseSdlTag from throwing exceptions when the input has ended.
  //       It may have been useful for an input buffered object, however, the buffered input object will
  //       need to know when it has a full tag anyway so the sdl will already contain the characters to end the tag.
  //       Or in the case of braces on the next line, if the tag has alot of whitespace until the actual end-of-tag
  //       delimiter, the buffered input reader can insert a semi-colon or open_brace to signify the end of the tag
  //       earlier.


  /// For now an alias for useStrictSdl. Use this function if you want your code to always use
  /// the default mode whatever it may become.
  alias useStrictSdl useDefaultSdl;

  /// This is the default mode.
  /// $(OL
  ///   $(LI Causes parseSdlTag to throw SdlParseException if a tag's open brace appears after a newline)
  ///   $(LI Causes parseSdlTag to throw SdlParseException if any tag value appears after any tag attribute)
  ///   $(LI Causes parseSdlTag to set anonymous tag names to "content")
  /// )
  void useStrictSdl() {
    this.allowMixedValuesAndAttributes = false;
    this.allowBraceAfterNewline = false;
    this.allowChildTagsOnSameLineAsBrace = false;
    this.anonymousTagNameIsNull = false;
    this.acceptUnquotedStrings = false;
  }
  /// $(OL
  ///   $(LI Causes parseSdlTag to throw SdlParseException if a tag's open brace appears after a newline)
  ///   $(LI Causes parseSdlTag to throw SdlParseException if any tag value appears after any tag attribute)
  ///   $(LI Causes parseSdlTag to set anonymous tag names to "content")
  /// )
  void useLooseSdl() {
    this.allowMixedValuesAndAttributes = true;
    this.allowBraceAfterNewline = true;
    this.allowChildTagsOnSameLineAsBrace = true;
    this.anonymousTagNameIsNull = false;
    this.acceptUnquotedStrings = true;
  }
  /// $(OL
  ///   $(LI Causes parseSdlTag to allow a tag's open brace appears after any number of newlines)
  ///   $(LI Causes parseSdlTag to allow tag values an attributes to mixed in any order)
  ///   $(LI Causes parseSdlTag to set anonymous tag names to null)
  /// )
  void useProposedSdl() {
    this.allowMixedValuesAndAttributes = true;
    this.allowBraceAfterNewline = true;
    this.allowChildTagsOnSameLineAsBrace = true;
    this.anonymousTagNameIsNull = true;
    this.acceptUnquotedStrings = true;
  }

  /// The depth of the tag, all root tags are at depth 0.
  size_t depth = 0;

  /// The line number of the SDL parser after parsing this tag.
  size_t line;
  size_t column;

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

  version(unittest_sdl)
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
  /// be reset by the parser on the next call to parseSdlTag when it calls $(D resetForNextTag()).
  void resetForNewSdl() {
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

  /// Returns true if the tag is anonymous.
  bool isAnonymous()
  {
    return anonymousTagNameIsNull ? this.name is null : this.name == "content";
  }
  /// Sets the tag as anonymous
  void setIsAnonymous()
  {
    this.name = anonymousTagNameIsNull ? null : "content";
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
    if(!isAnonymous || (values.data.length == 0 && attributes.data.length == 0)) {
      if(namespace.length == 0 && isSdlKeyword(name)) {
        sink.put(":"); // Escape tag names that are keywords
      }
      sink.put(name);
    }
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
  void getOneValue(T)(ref T value) {
    if(values.data.length != 1) {
      throw new SdlParseException
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

    if(!sdlLiteralToD!(T)(literal, value)) throw new SdlParseException(line, format("cannot convert '%s' to %s", literal, typeid(T)));
  }

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

bool isSdlKeyword(const char[] token) {
  return
    token == "null" ||
    token == "true" ||
    token == "false" ||
    token == "on" ||
    token == "off";
}
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



/// Converts literal to the given D type T.
/// This is a wrapper arround the $(D sdlLiteralToD) function that returns true on sucess, except
/// this function returns the value itself and throws an SdlParseException on error.
T sdlLiteralToD(T)(const(char)[] literal) {
  T value;
  if(!sdlLiteralToD!(T)(literal, value))
    throw new SdlParseException(format("failed to convert '%s' to a %s", literal, typeid(T)));
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
  if(range[0] == '\'') {
    if(range.length == 3 || (range.length == 4 && range[1] == '\\')) {
      if(range[$-1] != '\'') throw new Exception(format("a single-character range %s started with an apostrophe (') but did not end with one", range));
      return range ~ ":" ~ s[1] ~ rangeInitializersNext(s);
    }
  } else {
    throw new Exception(format("range '%s' not supported", range));
  }
  char min = range[1];
  char max = range[5];
  return arrayRange(min, max, s[1]) ~ rangeInitializersNext(s);
}
string rangeInitializersNext(string[] s...) {
  if(s.length <= 2) return "]";
  return ",\n"~rangeInitializersCurrent(s[2..$]);
}


enum ubyte sdlIDFlag                  = 0x01;
enum ubyte sdlNumberFlag              = 0x02;
enum ubyte sdlNumberPostfixFlag       = 0x04;
enum ubyte sdlValidAfterTagItemFlag   = 0x08;

version(use_lookup_tables) {
  mixin("private __gshared ubyte[256] sdlLookup = "~rangeInitializers
        ("'_'"    , "sdlIDFlag",

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

         `' '`    , "sdlValidAfterTagItemFlag",
         `'\t'`   , "sdlValidAfterTagItemFlag",
         `'\n'`   , "sdlValidAfterTagItemFlag",
         `'\v'`   , "sdlValidAfterTagItemFlag",
         `'\f'`   , "sdlValidAfterTagItemFlag",
         `'\r'`   , "sdlValidAfterTagItemFlag",

         `'{'`    , "sdlValidAfterTagItemFlag",
         `'}'`    , "sdlValidAfterTagItemFlag",
         `';'`    , "sdlValidAfterTagItemFlag",
         `'\\'`    , "sdlValidAfterTagItemFlag",
         `'/'`    , "sdlValidAfterTagItemFlag",
         `'#'`    , "sdlValidAfterTagItemFlag",


         )~";");
}

/// A convenience function to parse a single tag.
/// Calls $(D tag.resetForNewSdl) and then calls $(D parseSdlTag).
void parseOneSdlTag(Tag* tag, char[] sdlText) {
  tag.resetForNewSdl();
  if(!parseSdlTag(tag, &sdlText)) throw new SdlParseException(tag.line, format("The sdl text '%s' did not contain any tags", sdlText));
}

/// Parses one SDL tag (not including its children) from sdlText saving slices for every
/// name/value/attribute to the given tag struct.
/// This function assumes that sdlText contains at least one full SDL _tag.
/// The only time this function will allocate memory is if the value/attribute appenders
/// in the tag struct are not large enough to hold all the values.
/// Because of this, after the tag values/attributes are populated, it is up to the caller to copy
/// any memory they wish to save unless sdlText is going to persist in memory.
/// Note: this function does not handle the UTF-8 bom because it doesn't make sense to re-check
///       for the BOM before every tag.
/// Params:
///   tag = An address to a Tag structure to save the sdl tag's name/values/attributes.
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
  char[] tokenNamespace;
  char[] attributeID;
  char[] token;

  void enforceNoMoreTags() {
    if(tag.depth > 0) throw new SdlParseException(tag.line, format(notEnoughCloseBracesFmt, tag.depth));
  }

  void readNext()
  {
    cpos = next;
    c = decodeUtf8(&next, limit);
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
  bool isValidAfterTagItem() {
    version(use_lookup_tables) {
      return c < sdlLookup.length && ((sdlLookup[c] & sdlValidAfterTagItemFlag) != 0);
    } else {
      implement("isValidAfterTagItem without lookup table");
    }
  }
  bool isNumber() {
    version(use_lookup_tables) {
      return c < sdlLookup.length && ((sdlLookup[c] & sdlNumberFlag) != 0);
    } else {
      implement("isNumber without lookup table");
    }
  }
  bool isNumberPostfix() {
    version(use_lookup_tables) {
      return c < sdlLookup.length && ((sdlLookup[c] & sdlNumberPostfixFlag) != 0);
    } else {
      implement("isNumberPostfix without lookup table");
    }
  }

  // expected c/cpos to b pointing at a character before newline, so will ready first
  // before checking for newlines
  void toNextLine()
  {
    while(true) {
      if(next >= limit) { return; }
      c = decodeUtf8(&next, limit); // no need to save cpos since c will be thrown away
      if(c == '\n') { tag.line++; return; }
    }
  }

  // expects c/cpos to point at the first character of the id and for it to already be checked
  // when this function is done, c/cpos will pointing to the first character after the id, or
  // cpos == limit if there are no characters after the id
  void parseID()
  {
    while(true) {
      if(next >= limit) { cpos = limit; return; }
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
  // ExpectedState:
  //   c/cpos: points to the first character of the potential whitespace/comment
  // ReturnState:
  //   c/cpos: points to the first character after all the whitespace/comments
  bool skipWhitespaceAndComments()
  {
    LineNumber lineBefore = tag.line;

    while(true) {

      // TODO: maybe use a lookup table here
      if(c == ' ' || c == '\t' || c =='\v' || c == '\f' || c == '\r') {

        // do nothing (check first as this is the most likely case)

      } else if(c == '\n') {

        tag.line++;

      } else if(c == '#') {

        toNextLine();

      } else if(c == '-' || c == '/') {

        if(next >= limit) return tag.line > lineBefore;

        dchar secondChar = decodeUtf8(&next, limit);

        if(secondChar == c) { // '--' or '//'

          toNextLine();

        } else if(secondChar == '*') {

        MULTILINE_COMMENT_LOOP:
          while(next < limit) {

            c = decodeUtf8(&next, limit); // no need to save cpos since c will be thrown away
            if(c == '\n') {
              tag.line++;
            } else if(c == '*') {
              // loop assume c is pointing to a '*' and next is pointing to the next characer
              while(next < limit) {

                c = decodeUtf8(&next, limit);
                if(c == '/') break MULTILINE_COMMENT_LOOP;
                if(c == '\n') {
                  tag.line++;
                } else if(c != '*') {
                  break;
                }
              }
            }
          }

        } else {
          return tag.line > lineBefore;
        }

      } else {
        return tag.line > lineBefore;
      }

      //
      // Goto next character
      //
      if(next >= limit) {cpos = next; break;}
      readNext();
    }

    return tag.line > lineBefore;
  }


  // The atFirstToken will only parse tokens that are valid IDs
  // Expected State:
  //   tokenNamespace/attributeID to be empty (sets these if they are found)
  //   c/cpos: points at the first character of the token
  // Return State:
  //   If it finds a token, will set tokenNamespace and/or token with values
  //   c/cpos: points to the next character after the literal
  //   next: character after cpos
  void tryParseToken(bool atFirstToken) {
    token.length = 0; // clear the previous token

    // Handles
    //  tag name
    //  tag namespace/ tag name
    //  unquoted string
    //  attribute
    //  attribute with namespace, does not handle the value after the attribute
    if(isIDStart() || c == ':') { // colon for empty namespaces
      auto start = cpos;

      if(c != ':') {
        while(true) {
          cpos = next;
          if(next >= limit) { token = start[0..next-start]; return; }
          c = decodeUtf8(&next, limit);
          if(!isID()) break;
        }
      }

      // Handle Namespaces
      if(c == ':') {

        tokenNamespace = start[0..next-start]; // include the colon so the calling function
                                               // can differentiate between the empty namespace
                                               // and no namespace
        cpos = next;
        if(next >= limit) { token.length = 0; return; }
        c = decodeUtf8(&next, limit);

        if(!isIDStart()) {
          if(atFirstToken) {
            if(!isValidAfterTagItem()) throw new SdlParseException
                                         (tag.line, format("Character '%s' cannot appear after the tag's namespace", c));
            return;
          }
          throw new SdlParseException(tag.line,
                                      format("expected alphanum or '_' after an attribute namespace colon, but got '%s'", c));
        }

        start = cpos;
        while(true) {
          cpos = next;
          if(next >= limit) { token = start[0..next-start]; return; }
          c = decodeUtf8(&next, limit);
          if(!isID()) break;
        }

      }

      // Handle attributes
      if(c != '=') {
        if(!isValidAfterTagItem()) throw new SdlParseException
                                     (tag.line, format("Character '%s' cannot appear after tag item", c));
        token = start[0..next-start-1];
        return;
      }

      // Setup to parse the value
      attributeID = start[0..next-start-1]; // subtract 1 for the '='
      if(next >= limit) throw new SdlParseException
                          (tag.line, format("sdl cannot end with '=' character"));
      cpos = next;
      c = decodeUtf8(&next, limit);
    }


    // Handles: keywords and,
    //          unquoted strings in attribute values
    if(isIDStart()) {
      auto start = cpos;

      while(true) {
        cpos = next;
        if(next >= limit) { token = start[0..next-start]; return; }
        c = decodeUtf8(&next, limit);
        if(!isID()) break;
      }

      if(!isValidAfterTagItem()) throw new SdlParseException
                                   (tag.line, format("Character '%s' cannot appear after a tag item", c));

      token = start[0..next-start-1];
      return;
    }

    if(atFirstToken) return;

    if(c == '"') {

      bool containsEscapes = false;

      while(true) {

        if(next >= limit) throw new SdlParseException(tag.line, noEndingQuote);
        c = decodeUtf8(&next, limit); // no need to save cpos since c will be thrown away
        if(c == '"') break;
        if(c == '\\') {
          containsEscapes = true;
          if(next >= limit) throw new SdlParseException(tag.line, noEndingQuote);
          // NOTE TODO: remember to handle escaped newlines
          c = decodeUtf8(&next, limit);
        } else if(c == '\n') {
          throw new SdlParseException(tag.line, noEndingQuote);
        }

      }

      if(containsEscapes) {

        /* do something differnt if immuable */
        implement("escaped strings");

      } else {
        token = cpos[0..next - cpos];
      }

      cpos = next;
      if( next < limit) c = decodeUtf8(&next, limit);

    } else if(c == '`') {

      implement("tick strings");

    } else if(c >= '0' && c <= '9' || c == '-' || c == '.') {

      auto start = cpos;

      while(true) {
        cpos = next;
        if(next >= limit) { token = start[0..cpos-start]; break; }
        c = decodeUtf8(&next, limit);
        if(!isNumber()) { token = start[0..cpos-start]; break; }

        //if(tag.rejectTypedNumbers && isNumberPostfix())
        //throw new SdlParseException(tag.line, "using this sdl mode, postfix characters indicating the type after a number are not allowed");
      }

    } else if(c == '\'') {

      implement("sing-quoted characters");

    }
  }

  //
  // Read the first character
  //
  if(next >= limit) { enforceNoMoreTags(); goto RETURN_NO_TAG; }
  readNext();

  while(true) {

    skipWhitespaceAndComments();
    if(cpos >= limit) { enforceNoMoreTags(); goto RETURN_NO_TAG; }

    //
    //
    // Get the tag name/namespace
    //
    tokenNamespace.length = 0;
    attributeID.length = 0;
    tryParseToken(true);

    if(token.length || tokenNamespace.length) {

      if(attributeID.length) {

        tag.setIsAnonymous();

        if(tokenNamespace.length) tokenNamespace = tokenNamespace[0..$-1]; // Remove ending ':' on namespace
        Attribute attribute = {tokenNamespace, attributeID, token};
        tag.attributes.put(attribute);

      } else {

        if(tokenNamespace.length) {
          tag.namespace = tokenNamespace[0..$-1];
          if(token.length) {
            tag.name = token;
          } else {
            tag.setIsAnonymous();
            if(tag.namespace.length == 0)
              throw new SdlParseException(tag.line, "A tag cannot have an empty namespace and an empty name");
          }
        } else {

          if(isSdlKeyword(token)) {
            tag.setIsAnonymous();
            tag.values.put(token);
          } else {
            tag.name = token;
          }

        }

      }

    } else if(c == '}') {

      if(tag.depth == 0) throw new SdlParseException(tag.line, tooManyEndingBraces);
      tag.depth--;

      // Read the next character
      if(next >= limit) { enforceNoMoreTags(); goto RETURN_NO_TAG; }
      cpos = next;
      c = decodeUtf8(&next, limit);

      continue;

    } else if(c == '\\') {
      throw new SdlParseException(tag.line, "expected tag or '}' but got backslash '\\'");
    } else if(c == '{') {
      throw new SdlParseException(tag.line, "expected tag or '}' but got '{'");
    } else if(c == ':') {
      throw new SdlParseException(tag.line, "expected tag or '}' but got ':'");
    } else {

      tag.namespace.length = 0;
      tag.setIsAnonymous();

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
      if(cpos >= limit) goto RETURN_TAG;
      if(foundNewline) {

        // check if it is a curly brace to either print a useful error message
        // or determine if the tag has children
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
        c = decodeUtf8(&next, limit);

        foundNewline = skipWhitespaceAndComments();
        if(cpos >= limit) goto RETURN_TAG;
        if(!foundNewline) throw new SdlParseException(tag.line, "only comments/whitespace can follow a backslash '\\'");

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
      tokenNamespace.length = 0;
      attributeID.length = 0;
      tryParseToken(false);
      if(token.length || tokenNamespace.length) {

        if(attributeID.length > 0) {
          if(tokenNamespace.length) tokenNamespace = tokenNamespace[0..$-1]; // Remove ending ':' on namespace
          Attribute attribute = {tokenNamespace, attributeID, token};
          tag.attributes.put(attribute);
        } else {

          if(tokenNamespace.length)
            throw new SdlParseException(tag.line, format("Found a tag value with a namespace '%s%s'?", tokenNamespace, token));

          if(tag.attributes.data.length) {
            if(!tag.allowMixedValuesAndAttributes)
              throw new SdlParseException(SdlErrorType.mixedValuesAndAttributes, tag.line,
                                          format(mixedValuesAndAttributesFmt, token, tag.name));
          }

          tag.values.put(token);
        }

        if(cpos >= limit) goto RETURN_TAG;

      } else {

        if(attributeID.length > 0) throw new SdlParseException(tag.line, "expected sdl literal to follow attribute '=' but was not a literal");

        if(c == '\0') throw new Exception("possible code bug: found null");
        throw new Exception(format("Unhandled character '%s' (code=0x%x)", c, cast(uint)c));

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


version(unittest_sdl) unittest
{
  //return; // Uncomment to disable these tests

  mixin(scopedTest!"SdlParse");

  Tag parsedTag;

  void useProposed() {
    debug writefln("[TEST] SdlMode: Proposed");
    parsedTag.useProposedSdl();
  }
  void useStrict() {
    debug writefln("[TEST] SdlMode: Strict");
    parsedTag.useStrictSdl();
  }
  struct SdlTest
  {
    bool copySdl;
    string sdlText;
    Tag[] expectedTags;
    size_t line;
    this(string sdlText, Tag[] expectedTags, size_t line = __LINE__) {
      this.copySdl = false;
      this.sdlText = sdlText;
      this.expectedTags = expectedTags;
      this.line = line;
    }
  }

  void testParseSdl(bool reparse = true)(bool copySdl, const(char)[] sdlText, Tag[] expectedTags = [], size_t line = __LINE__)
  {
    size_t previousDepth = size_t.max;
    SdlBuffer2Sink buffer2Sink;

    auto escapedSdlText = escape(sdlText);

    debug {
      static if(reparse) {
        writefln("[TEST] testing sdl              '%s'", escapedSdlText);
      } else {
        writefln("[TEST] testing sdl (regenerated)'%s'", escapedSdlText);
      }
    }

    char[] next = setupSdlText(sdlText, copySdl);

    parsedTag.resetForNewSdl();


    try {

      for(auto i = 0; i < expectedTags.length; i++) {
        if(!parseSdlTag(&parsedTag, &next)) {
          writefln("Expected %s tag(s) but only got %s", expectedTags.length, i);
          writefln("Error: test on line %s", line);
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
          writefln("Error: test on line %s", line);
          assert(0);
        }
        if(parsedTag.name != expectedTag.name) {
          writefln("Error: expected tag name '%s' but got '%s'", expectedTag.name, parsedTag.name);
          writefln("Error: test on line %s", line);
          assert(0);
        }
        //writefln("[DEBUG] expected value '%s', actual values '%s'", expectedTag.values.data, parsedTag.values.data);
        if(parsedTag.values.data != expectedTag.values.data) {
          writefln("Error: expected tag values '%s' but got '%s'", expectedTag.values.data, parsedTag.values.data);
          writefln("Error: test on line %s", line);
          assert(0);
        }
        if(parsedTag.attributes.data != expectedTag.attributes.data) {
          writefln("Error: expected tag attributes '%s' but got '%s'", expectedTag.attributes.data, parsedTag.attributes.data);
          writefln("Error: test on line %s", line);
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
        writefln("Error: test on line %s", line);
        assert(0);
      }

    } catch(SdlParseException e) {
      writefln("[TEST] this sdl threw an unexpected SdlParseException: '%s'", escape(sdlText));
      writeln(e);
      writefln("Error: test on line %s", line);
      assert(0);
    } catch(Exception e) {
      writefln("[TEST] this sdl threw an unexpected Exception: '%s'", escape(sdlText));
      writeln(e);
      writefln("Error: test on line %s", line);
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
        testParseSdl!false(false, buffer2Sink.slice, expectedTags, line);
      }
    }

  }

  void testInvalidSdl(bool copySdl, const(char)[] sdlText, SdlErrorType expectedErrorType = SdlErrorType.unknown, size_t line = __LINE__) {
    auto escapedSdlText = escape(sdlText);
    debug writefln("[TEST] testing invalid sdl '%s'", escapedSdlText);

    SdlErrorType actualErrorType = SdlErrorType.unknown;

    char[] next = setupSdlText(sdlText, copySdl);

    parsedTag.resetForNewSdl();
    try {
      while(parseSdlTag(&parsedTag, &next)) { }
      writefln("Error: invalid sdl was successfully parsed: %s", sdlText);
      writefln("Error: test was on line %s", line);
      assert(0);
    } catch(SdlParseException e) {
      debug writefln("[TEST]    got expected error: %s", e.msg);
      actualErrorType = e.type;
    } catch(Utf8Exception e) {
      debug writefln("[TEST]    got expected error: %s", e.msg);
    }

    if(expectedErrorType != SdlErrorType.unknown &&
       expectedErrorType != actualErrorType) {
      writefln("Error: expected error '%s' but got error '%s'", expectedErrorType, actualErrorType);
      writefln("Error: test was on line %s", line);
      assert(0);
    }

  }

  testParseSdl(false, "");
  testParseSdl(false, "  ");
  testParseSdl(false, "\n");

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

  testParseSdl(false, "/* a multiline comment \n\r\n\n\n\t hello stuff # -- // */");

  // TODO: test this using the allowBracesAfterNewline option
  //  testParseSdl(false, "tag /*\n\n*/{ child }", Tag("tag"), Tag("child"));


  testParseSdl(false, "a", [Tag("a")]);
  testParseSdl(false, "ab", [Tag("ab")]);
  testParseSdl(false, "abc", [Tag("abc")]);
  testParseSdl(false, "firsttag", [Tag("firsttag")]);
  testParseSdl(false, "funky._-$tag", [Tag("funky._-$tag")]);


  {
    auto prefixes = ["", " ", "\t", "--comment\n"];
    foreach(prefix; prefixes) {
      testInvalidSdl(false, prefix~":");
    }
  }


  auto validCharactersAfterTag =
    [" ", "\t", "\n", "\v", "\f", "\r", ";", "//", "\\", "#", "{}"];


  auto namespaces = ["a:", "ab:", "abc:"];
  bool isProposedSdl = false;
  while(true) {
    string tagName;
    if(isProposedSdl) {
      tagName = null;
      useProposed();
    } else {
      tagName = "content";
    }
    foreach(namespace; namespaces) {
      testParseSdl(false, namespace, [Tag(namespace~tagName)]);
      foreach(suffix; validCharactersAfterTag) {
        testParseSdl(false, namespace~suffix, [Tag(namespace~tagName)]);
      }
      testParseSdl(false, "tag1{"~namespace~"}", [Tag("tag1"), Tag(namespace~tagName)]);
    }
    if(isProposedSdl) break;
    isProposedSdl = true;
  }
  useStrict();


  testParseSdl(false, "a:a", [Tag("a:a")]);
  testParseSdl(false, "ab:a", [Tag("ab:a")]);

  testParseSdl(false, "a:ab", [Tag("a:ab")]);
  testParseSdl(false, "ab:ab", [Tag("ab:ab")]);

  testParseSdl(false, "html:table", [Tag("html:table")]);

  testParseSdl(false, ";", [Tag("content")]);
  testParseSdl(false, "myid;", [Tag("myid")]);
  testParseSdl(false, "myid;   ", [Tag("myid")]);
  testParseSdl(false, "myid #comment", [Tag("myid")]);
  testParseSdl(false, "myid # comment \n", [Tag("myid")]);
  testParseSdl(false, "myid -- comment \n # more comments\n", [Tag("myid")]);


  testParseSdl(false, "myid /* multiline comment */", [Tag("myid")]);
  testParseSdl(false, "myid /* multiline comment */ ", [Tag("myid")]);
  testParseSdl(false, "myid /* multiline comment */\n", [Tag("myid")]);
  testParseSdl(false, "myid /* multiline comment \n\n */", [Tag("myid")]);
  testParseSdl(false, "myid /* multiline comment **/ \"value\"", [Tag("myid", `"value"`)]);
  testParseSdl(false, "myid /* multiline comment \n\n */another-id", [Tag("myid"), Tag("another-id")]);
  testParseSdl(false, "myid /* multiline comment */ \"value\"", [Tag("myid", `"value"`)]);
  testParseSdl(false, "myid /* multiline comment \n */ \"value\"", [Tag("myid"), Tag("content", `"value"`)]);
  testInvalidSdl(false, "myid /* multiline comment \n */ { \n }");
  useProposed();
  testParseSdl(false, "myid /* multiline comment */ { \n }", [Tag("myid")]);
  testParseSdl(false, "myid /* multiline comment \n */ \"value\"", [Tag("myid"), Tag(null, `"value"`)]);
  useStrict();


  testParseSdl(false, "tag1\ntag2", [Tag("tag1"), Tag("tag2")]);
  testParseSdl(false, "tag1;tag2\ntag3", [Tag("tag1"), Tag("tag2"), Tag("tag3")]);

  testInvalidSdl(false, "myid {");
  testInvalidSdl(false, "myid {\n\n");

  testInvalidSdl(false, "{}");

  testParseSdl(false, "tag1{}", [Tag("tag1")]);
  testParseSdl(false, "tag1{}tag2", [Tag("tag1"), Tag("tag2")]);
  testParseSdl(false, "tag1{}\ntag2", [Tag("tag1"), Tag("tag2")]);

  testParseSdl(false, "tag1{tag1.1}tag2", [Tag("tag1"), Tag("tag1.1"), Tag("tag2")]);

  //
  // Handling the backslash '\' character
  //
  testInvalidSdl(false, "\\"); // slash must in the context of a tag
  testInvalidSdl(false, `tag \ x`);

  testParseSdl(false, "tag\\", [Tag("tag")]); // Make sure this is valid sdl
  testParseSdl(false, "tag \\  \n \\ \n \"hello\"", [Tag("tag", `"hello"`)]);

  //
  // Test the keywords (white box tests trying to attain full code coverage)
  //
  auto keywords = ["null", "true", "false", "on", "off"];

  foreach(keyword; keywords) {
    testParseSdl(false, keyword, [Tag("content", keyword)]);
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
        //testInvalidSdl(false, sdlBuffer[0..afterTagName+cutoff]);
        testParseSdl(false, sdlBuffer[0..afterTagName+cutoff], [Tag(expectedTagName, sdlBuffer[afterTagName..afterTagName+cutoff])]);
      }
    }
    auto suffixes = [";", " \t;", "\n", "{}", " \t {\n }"];
    foreach(keyword; keywords) {
      auto limit = afterTagName+keyword.length;

      sdlBuffer[afterTagName..limit] = keyword;
      testParseSdl(false, sdlBuffer[0..limit], [Tag(expectedTagName, keyword)]);

      foreach(suffix; suffixes) {
        sdlBuffer[limit..limit+suffix.length] = suffix;
        testParseSdl(false, sdlBuffer[0..limit+suffix.length], [Tag(expectedTagName, keyword)]);
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
          testParseSdl(false, sdlBuffer[0..limit+8], [Tag(expectedTagName, format(`%s%s="value"`, attrNamespace, keyword[0..cutoff]))]);

          foreach(otherKeyword; keywords) {
            sdlBuffer[limit+1..limit+1+otherKeyword.length] = otherKeyword;
            testParseSdl(false, sdlBuffer[0..limit+1+otherKeyword.length],
                         [Tag(expectedTagName, format("%s%s=%s", attrNamespace, keyword[0..cutoff], otherKeyword))]);
          }
        }

      }

    }
  }




  //
  // String Literals
  //
  testParseSdl(false, `a "apple"`, [Tag("a", `"apple"`)]);
  testParseSdl(false, "a \"pear\"\n", [Tag("a", `"pear"`)]);
  testParseSdl(false, "a \"left\"\nb \"right\"", [Tag("a", `"left"`), Tag("b", `"right"`)]);
  testParseSdl(false, "a \"cat\"\"dog\"\"bear\"\n", [Tag("a", `"cat"`, `"dog"`, `"bear"`)]);
  testParseSdl(false, "a \"tree\";b \"truck\"\n", [Tag("a", `"tree"`), Tag("b", `"truck"`)]);


  //
  // Unquoted Strings
  //
  testParseSdl(false, "tag string", [Tag("tag", "string")]);
  testParseSdl(false, "tag attr=string", [Tag("tag", "attr=string")]);



  //
  // Attributes
  //
  testParseSdl(false, "tag attr=null", [Tag("tag", "attr=null")]);
  testParseSdl(false, "tag \"val\" attr=null", [Tag("tag", `"val"`, "attr=null")]);

  auto mixedValuesAndAttributesTests =
    [
     SdlTest("tag attr=null \"val\"", [Tag("tag", "attr=null", `"val"`)] )
     ];

  foreach(test; mixedValuesAndAttributesTests) {
    testInvalidSdl(test.copySdl, test.sdlText, SdlErrorType.mixedValuesAndAttributes);
  }
  useProposed();
  foreach(test; mixedValuesAndAttributesTests) {
    testParseSdl(test.copySdl, test.sdlText, test.expectedTags);
  }
  useStrict();

  foreach(suffix; validCharactersAfterTag) {
    testParseSdl(false, "tag attr=null"~suffix, [Tag("tag", "attr=null")]);
    testParseSdl(false, "tag attr=true"~suffix, [Tag("tag", "attr=true")]);
    testParseSdl(false, "tag attr=unquoted"~suffix, [Tag("tag", "attr=unquoted")]);
    testParseSdl(false, "tag attr=\"quoted\""~suffix, [Tag("tag", "attr=\"quoted\"")]);
    testParseSdl(false, "tag attr=1234"~suffix, [Tag("tag", "attr=1234")]);

    testParseSdl(false, "attr=null"~suffix, [Tag("content", "attr=null")]);
    testParseSdl(false, "attr=true"~suffix, [Tag("content", "attr=true")]);
    testParseSdl(false, "attr=unquoted"~suffix, [Tag("content", "attr=unquoted")]);
    testParseSdl(false, "attr=\"quoted\""~suffix, [Tag("content", "attr=\"quoted\"")]);
    testParseSdl(false, "attr=1234"~suffix, [Tag("content", "attr=1234")]);
  }

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
            //testInvalidSdl(false, "tag "~testNumber);
            useStrict();
          }
          //testInvalidSdl(false, "tag "~testNumber~"=");

          foreach(sdlPostfix; sdlPostfixes) {
            testParseSdl(false, "tag "~testNumber~sdlPostfix, [Tag("tag", testNumber)]);
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

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"0"~postfix);
        testNumberOnAllTypes(0);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"1"~postfix);
        testNumberOnAllTypes(1);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"12"~postfix);
        testNumberOnAllTypes(12);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"9987"~postfix);
        testNumberOnAllTypes(9987);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"0.0"~postfix);
        testDecimalNumberOnAllTypes(0.0);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~".1"~postfix);
        testDecimalNumberOnAllTypes(0.1);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~".000001"~postfix);
        testDecimalNumberOnAllTypes(0.000001);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"100384.999"~postfix);
        testDecimalNumberOnAllTypes(100384.999);

        parseOneSdlTag(&parsedTag, cast(char[])"tag "~prefix~"3.14159265"~postfix);
        testDecimalNumberOnAllTypes(3.14159265);
      }
    }

  }


  //
  // Children
  //
  testInvalidSdl(false, "{}"); // no line can start with a curly brace

  auto braceAfterNewlineTests =
    [
     SdlTest("tag\n{  child\n}", [Tag("tag"), Tag("child")]),
     SdlTest("colors \"hot\" \n{  yellow\n}", [Tag("colors", `"hot"`), Tag("yellow")])
     ];

  foreach(test; braceAfterNewlineTests) {
    testInvalidSdl(test.copySdl, test.sdlText, SdlErrorType.braceAfterNewline);
  }
  useProposed();
  foreach(test; braceAfterNewlineTests) {
    testParseSdl(test.copySdl, test.sdlText, test.expectedTags);
  }
  useStrict();

  //
  // Odd corner cases
  //
  testParseSdl(false, "tag null;", [Tag("tag", "null")]);
  testParseSdl(false, "tag null{}", [Tag("tag", "null")]);
  testParseSdl(false, "tag true;", [Tag("tag", "null")]);
  testParseSdl(false, "tag true{}", [Tag("tag", "null")]);
  testParseSdl(false, "tag false;", [Tag("tag", "null")]);
  testParseSdl(false, "tag false{}", [Tag("tag", "null")]);

  testParseSdl(false, "namespace:true", [Tag("namespace:true")]);
  testParseSdl(false, ":true", [Tag("true")]);
  testParseSdl(false, "true", [Tag("content", "true")]);
  testParseSdl(false, "tag\\", [Tag("tag")]);
  testParseSdl(false, "tag/*comment*/null", [Tag("tag", "null")]);
  testParseSdl(false, "crazy--tag", [Tag("crazy--tag")]);
  testParseSdl(false, "tag# comment", [Tag("tag")]);
  testParseSdl(false, "tag// comment", [Tag("tag")]);
  testParseSdl(false, "a=what", [Tag("content", "a=what")]);

  testParseSdl(false, "tag {\nattr=value//\n}", [Tag("tag"), Tag("content", "attr=value")]);
  testParseSdl(false, "tag {\nattr=value}", [Tag("tag"), Tag("content", "attr=value")]);


  testInvalidSdl(false, "tag what/huh");
  testInvalidSdl(false, `tag"value"`);
  testInvalidSdl(false, "attr:123");
  testInvalidSdl(false, "attr:\"what\"");
  testInvalidSdl(false, "attr:=what");
  testInvalidSdl(false, "attr:=null");
  testInvalidSdl(false, "attr:=345");
  testInvalidSdl(false, "name:tag:weird");
  testInvalidSdl(false, "tag namespace:what");
  testInvalidSdl(false, "tag namespace:\"value\"");
  testInvalidSdl(false, "tag namespace:null");
  testInvalidSdl(false, "tag namespace:true");
  testInvalidSdl(false, "tag^");
  testInvalidSdl(false, "tag<");
  testInvalidSdl(false, "tag>");





  // TODO: testing using all keywords as namespaces true:id, etc.
  testParseSdl(false, "tag null:null=\"value\";", [Tag("tag", "null:null=\"value\"")]);
  testParseSdl(false, "null", [Tag("content", "null")]);



  //
  // Full Parses
  //
  testParseSdl(false, `
name "joe"
children {
  name "jim"
}`, [Tag("name", `"joe"`), Tag("children"), Tag("name", `"jim"`)]);

  testParseSdl(false, `
parent name="jim" {
  child "hasToys" name="joey" {
     # just a comment here for now
  }
}`, [Tag("parent", "name=\"jim\""), Tag("child", "name=\"joey\"", `"hasToys"`)]);


  testParseSdl(false,`td 34
html:td "Puggy"
`, [Tag("td", `34`),
    Tag("html:td", `"Puggy"`)]);


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
    html:td null
    html:td false
  }
  tr {
    td "Jackie"
    td 27
    td null
  }
}`, [Tag("html:table"),
      Tag("html:tr"),
        Tag("html:th", `"Name"`),
        Tag("html:th", `"Age"`),
        Tag("html:th", `"Pet"`),
      Tag("html:tr"),
        Tag("html:td", `"Brian"`),
        Tag("html:td", `34`),
        Tag("html:td", `"Puggy"`),
        Tag("html:td", `null`),
        Tag("html:td", `false`),
      Tag("tr"),
        Tag("td", `"Jackie"`),
        Tag("td", `27`),
        Tag("td", `null`)]);
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
  ///          tags at the given depth. If depth is 0 it means the sdl has been fully parsed.
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
}

version(unittest_sdl)
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


version(unittest_sdl) unittest
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
}

version(unittest_sdl) unittest
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
      children.length = 0;
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
          child.parseFromSdl(walker);
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

}

