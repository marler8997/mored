/**
   Examples:
   --------------------------------
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
       void validate() {
           if(name == null) throw new Exception("person is missing the 'name' tag");
           if(age == 0) throw new Exception("person is missing the 'age' tag");
       }
   }
   
   char[] sdl;

   // ...read SDL into char[] sdl

   Person p;
   parseSdlInto!Person(sdl);
   ----------------------------------
   



 */
module more.sdlreflection;

import std.string;
import std.conv;
import std.typecons;
import std.traits;
import std.range;
import std.array;
import std.meta : AliasSeq;

import more.common;
import more.sdl;

version(unittest)
{
  import std.stdio;
}

version = DebugSdlReflection;

string debugSdlReflection(string object, string member, string message, bool submessage = false)
{
  return format("version(DebugSdlReflection) pragma(msg, \"[DebugSdlReflection] %s%s.%s %s\");",
		submessage ? "    " : "", object, member, message);
}



/// An enum of sdl reflection options to be used as custom attributes.
/// If an option requires arguments pass then in as an argument list
enum SdlReflection {
  /// Indicates the SDL parser should ignore this member
  ignore,

  /// Prevents SDL from specifying a list type as individual tags. TODO provide example.
  noSingularTags,

  /// Only allows the list items to appear one at a time in the SDL using
  /// the singular version of the list member name
  onlySingularTags,
}


/// An SDL Reflection Attribute.
/// If singularName is not specified, then it will try to determine the singularName
/// by removing the ending 's' from the member name.
/// If the member name does not end in an 's' it will assert an error if noSingularTags
/// is not true.  The singularName is used to determine what a tag-name should be when
/// someone wants to list elements of the array one at a time in the SDL.  For example, if the
/// member is an array of strings called "names", the default singular will be "name".
struct SdlSingularName
{
  string name;
}

private template containsFlag(SdlReflection flag, A...) {
  static if (A.length == 0) {
    enum containsFlag = false;
  } else static if ( is( typeof(A[0]) == SdlReflection ) && A[0] == flag ) {
    enum containsFlag = true;
  } else  {
    enum containsFlag = containsFlag!(flag, A[1..$]);
  }
}
private template singularName(structType, string memberString) {
  alias singularName = singularNameRecursive!(memberString, __traits(getAttributes, __traits(getMember, structType, memberString)));
}
private template singularNameRecursive(string memberString, A...) {
  static if(A.length == 0) {
    static if(memberString[$-1] == 's') {
      enum singularNameRecursive = memberString[0..$-1];
    } else {
      enum singularNameRecursive = null;
    }
  } else static if( is( typeof(A[0]) == SdlSingularName ) ) {
    enum singularNameRecursive = A[0].name;
  } else {
    enum singularNameRecursive = singularNameRecursive!(memberString, A[1..$]);
  }
}


/+
template isOutRange(R) {
  enum isOutRange = is( typeof(__traits(getMember, R, "put")) == function );
}
+/
template AppenderElementType(T) {
  static if( !__traits(hasMember, T, "data") ) {
    alias AppenderElementType = void;
  } else static if( is( ElementType!(typeof(__traits(getMember, T, "data"))) == void) )  { 
    alias AppenderElementType = void;
  } else {
    alias AppenderElementType = Unqual!(ElementType!(typeof(__traits(getMember, T, "data"))));
  }
}

static assert(is( AppenderElementType!(Appender!(int[])) == int));
static assert(is( AppenderElementType!(Appender!(string[])) == string));

static assert(is( Appender!(AppenderElementType!(Appender!(int[]))[]) == Appender!(int[])));
static assert(is( Appender!(AppenderElementType!(Appender!(string[]))[]) == Appender!(string[])));


void parseSdlInto(T)(ref T obj, string sdl)
{
  Tag tag;
  tag.preserveSdlText = true; // Make sure that the sdl is not modified because it is a string
  SdlWalker walker = SdlWalker(&tag, sdl);

  debug writefln("[DEBUG] parseSdlInto: --> (Type=%s)", T.stringof);
  parseSdlInto(obj, walker, sdl, 0);
  debug writefln("[DEBUG] parseSdlInto: <--");
}
void parseSdlInto(T)(ref T obj, char[] sdl)
{
  Tag tag;
  SdlWalker walker = SdlWalker(&tag, sdl);

  debug writefln("[DEBUG] parseSdlInto: --> (Type=%s)", T.stringof);
  parseSdlInto(obj, walker, sdl, 0);
  debug writefln("[DEBUG] parseSdlInto: <--");
}
void parseSdlInto(T)(ref T obj, ref SdlWalker walker, char[] sdl, size_t depth) if( is( T == struct) )
{
  Tag* tag = walker.tag;
  
  if(depth > 0) {
    //
    // Process attributes and values
    //
    implement("object values and attributes");
  }

 TAG_LOOP:
  while(walker.pop(depth)) {

    debug writefln("[DEBUG] parseSdlInto: at depth %s tag '%s'", tag.depth, tag.name);

    foreach(memberIndex, copyOfMember; obj.tupleof) {
    
      alias typeof(T.tupleof[memberIndex]) memberType;
      enum memberString = T.tupleof[memberIndex].stringof;

      //writefln("[DEBUG] tag '%s' checking member '%s %s'", tag.name, memberType.stringof, memberString);

      alias AliasSeq!(__traits(getAttributes, T.tupleof[memberIndex])) memberAttributes;
      alias ElementType!(memberType) memberElementType;
      enum isAppender = is( memberType == Appender!(AppenderElementType!(memberType)[]));

      static if(memberString == "this") {

	mixin(debugSdlReflection(T.stringof, memberString, "ignored because 'this' is always ignored"));
	
      } else static if(containsFlag!(SdlReflection.ignore, memberAttributes)) {

	mixin(debugSdlReflection(T.stringof, memberString, "ignored from SdlReflection.ignore"));

      } else static if( is( memberType == function) ) {

	mixin(debugSdlReflection(T.stringof, memberString, "ignored because it is a function"));

      } else static if( isAppender || ( !is( memberElementType == void ) && !isSomeString!(memberType) ) ) {


	static if(isAppender) {
	  mixin(debugSdlReflection(T.stringof, memberString, "deserialized as a list, specifically an appender"));

	  template addValues(string memberName) {
	    void addValues() {
	      auto elementOffset = __traits(getMember, obj, memberString).data.length;
	      __traits(getMember, obj, memberString).reserve(elementOffset + tag.values.data.length);
	      AppenderElementType!(memberType) deserializedValue;

	      foreach(value; tag.values.data) {
		if(!sdlLiteralToD!(AppenderElementType!(memberType))( value, deserializedValue)) {
		  throw new SdlParseException(tag.line, format("failed to convert '%s' to %s for appender %s.%s",
							       value, memberElementType.stringof, T.stringof, memberString) );
		}
		__traits(getMember, obj, memberString).put(deserializedValue);
		elementOffset++;
	      }
	    }
	  }

	} else {

	  mixin(debugSdlReflection(T.stringof, memberString, "deserialized as a list, specifically an array"));

	  template addValues(string memberName) {
	    void addValues() {
	      auto elementOffset = __traits(getMember, obj, memberString).length;

	      __traits(getMember, obj, memberString).length += tag.values.data.length;
	      foreach(value; tag.values.data) {
		if(!sdlLiteralToD!(memberElementType)( value, __traits(getMember, obj, memberString)[elementOffset] ) ) {
		  throw new SdlParseException(tag.line, format("failed to convert '%s' to %s for array member %s.%s",
							       value, memberElementType.stringof, T.stringof, memberString) );
		}
		elementOffset++;
	      }
	    }
	  }

	}

	static if(containsFlag!(SdlReflection.onlySingularTags, memberAttributes)) {
	  mixin(debugSdlReflection(T.stringof, memberString, format("onlySingularTags so will not handle tags named '%s'", memberString), true));
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
		  throw new SdlParseException(tag.line, format("the child elements of array member %s.%s can only use anonymous tags, but found a tag with name '%s'",
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

	static if(containsFlag!(SdlReflection.noSingularTags, memberAttributes) ) {
	  mixin(debugSdlReflection(T.stringof, memberString, "does not handle singular tags", true));
	} else {
	  static if(singularName!(T, memberString) is null) {
	    static assert(0, format("Could not determine the singular name for %s.%s because it does not end with an 's'.  Use @(SdlSingularName(\"name\") to specify one.",
				    T.stringof, memberString));
	  }

	  mixin(debugSdlReflection(T.stringof, memberString, format("handles singular tags named '%s'", singularName!(T, memberString)), true));


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
	      debug writefln("[DEBUG] parseSdlInto: %s.%s was appended with '%s'", T.stringof, memberString, __traits(getMember, obj, memberString));
	      continue TAG_LOOP;
		    
	    }

	  }
	    
	}

	// END OF HANDLING OUTPUT RANGES

      } else static if( isAssociativeArray!(memberType)) {

	mixin(debugSdlReflection(T.stringof, memberString, "deserialized as an associative array"));
	implement("associative arrays");

      } else static if( is (isNested!(memberType))) {

	mixin(debugSdlReflection(T.stringof, memberString, "deserialized as an object"));
	implement("sub function/struct/class");

      } else {

	mixin(debugSdlReflection(T.stringof, memberString, "deserialized as a single value"));
	
	if(tag.name == memberString) {
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(__traits(getMember, obj, memberString));
	  debug writefln("[DEBUG] parseSdlInto: set %s.%s to '%s'", T.stringof, memberString, __traits(getMember, obj, memberString));
	  continue TAG_LOOP;
	}


      }

    }

    tag.throwIsUnknown();
  }

}



















/+
string enumerateTraits(string fmt, string value) {
  string code = "";
  code != "if( format(fmt, format("__traits(
}
+/


version(unittest_sdlreflection) unittest
{
  mixin(scopedTest!("SdlReflection"));

  void testParseType(T)(bool copySdl, string sdlText, T expectedType)
  {
    T parsedType;

    try {
      
      parseSdlInto!T(parsedType, setupSdlText(sdlText, copySdl));

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
    @(SdlReflection.ignore)
    string ignoreThisMember;

    string name;
    private string privateName;
    uint packageID;

    uint[] randomUints;

    string[] authors;

    @(SdlReflection.noSingularTags)
    string[] sourceFiles;

        
    @(SdlSingularName("dependency"))
    string[string][] dependencies;

    @(SdlReflection.onlySingularTags)
    @(SdlSingularName("a-float"))
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



/+
  testParseType(false, `

`, Appender!(int[])());
+/

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

