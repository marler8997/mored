module more.sdlreflection;

import std.string;
import std.conv;
import std.typecons;
import std.traits;

import more.common;
import more.sdl;

version(unittest)
{
  import std.stdio;
}



/// An enum of sdl reflection options to be used as custom attributes.
/// If an option requires arguments pass then in as an argument list
enum SdlReflection {
  //
  // Generic member properties
  //

  /// Indicates the SDL parser should ignore this member
  ignore,

  //
  // List Properties (array or Appender)
  //

  //
  // Object Properties
  //


  // TODO: could add a FinishValidator attribute
}


/// An SDL Reflection Attribute.
/// If singularName is not specified, then it will try to determine the singularName
/// by removing the ending 's' from the member name.
/// If the member name does not end in an 's' it will assert an error if preventSingular
/// is not true.  The singularName is used to determine what a tag-name should be when
/// someone wants to specify one member of an array of this member.  For example, if the
/// member is an array of strings called "names", the default singular will be "name".
struct SdlSingularName
{
  string name;
}
  




void parseInto(T)(ref T obj, char[] sdl)
{
  Tag tag;
  SdlWalker walker = SdlWalker(&tag, sdl);

  writefln("[DEBUG] parseInto start!");
  parseInto(obj, walker, sdl, 0);

  // TODO: assert that walker has finished
}
void parseInto(T)(ref T obj, ref SdlWalker walker, char[] sdl, size_t depth)
{
  writefln("[DEBUG]      parsing '%s'", typeid(T));

  Tag* tag = walker.tag;

  
  if(tag.depth > 0) {
    //
    // Process attributes and values
    //
    implement("object values and attributes");
  }

 TAG_LOOP:
  while(walker.pop(depth)) {

    writefln("[DEBUG] parseInto: at depth %s tag '%s'", tag.depth, tag.name);

  MEMBER_LOOP:
    foreach(memberString; __traits(allMembers, T)) {
      writefln("[DEBUG]    member '%s'", memberString);

      foreach(attribute; __traits(getAttributes, __traits(getMember, T, memberString))) {
	writefln("[DEBUG]         member '%s' attribute '%s'", memberString, attribute);
	static if( is( typeof(attribute) == SdlReflection ) ) {

	  static if(attribute == SdlReflection.ignore) {
	    writefln("[DEBUG]         ignoring member '%s'", memberString);
	    continue MEMBER_LOOP;
	  } else {
	    static assert(0, format("Attribute @(%s) on member %s.%s is unknown", attribute, T.stringof, memberString));
	  }

	} else static if( is( typeof(attribute) == SdlSingularName) ) {
	    
	    static assert(isArray!(typeof(__traits(getMember, T, memberString))),
		   format("The SdlSingularName attribute can only be applied to array types, but you applied it to %s.%s of type %s",
			  T.stringof, memberString, typeid(__traits(getMember, T, memberString))));
	    //writefln("  SdlSingularName '%s'", attribute.name);

        } else {
	  writefln("[DEBUG]         attribute '%s' (type=%s)", attribute, typeid(attribute));
	}

      }



      static if (isSomeString!(typeof(__traits(getMember, T, memberString)))) {
	if(tag.name == memberString) {
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(__traits(getMember, obj, memberString));
	  writefln("[DEBUG] set %s.%s to '%s'", T.stringof, memberString, __traits(getMember, obj, memberString));
	  continue TAG_LOOP;
	}
      } else static if( isArray!(typeof(__traits(getMember, T, memberString)))) {

	if(tag.name == memberString) {
	  assert(0, format("Arrays not implemented yet...at %s.%s", T.stringof, memberString));
	}
	    // TODO: check singular name

      } else static if( isAssociativeArray!(typeof(__traits(getMember, T, memberString)))) {
	assert(0);
      } else {

	// TODO: can I make this static !!!!
	if(tag.name == memberString) {
	  tag.enforceNoAttributes();
	  tag.enforceNoChildren();
	  tag.getOneValue(__traits(getMember, obj, memberString));
	  writefln("[DEBUG] set %s.%s to '%s'", T.stringof, memberString, __traits(getMember, obj, memberString));
	  continue TAG_LOOP;
	}
      }



    }

    throw new SdlParseException(tag.line, format("Unknown tag name '%s'", tag.name));

  }

  writefln("[DEBUG] done parsing '%s'", T.stringof);

}



unittest
{
  mixin(scopedTest!("SdlReflection"));

  struct PackageInfo
  {
    @(SdlReflection.ignore)
    string ignoreThisMember;

    string name;
    uint packageID;

    ubyte[] randomBytes;
        
    string[] authors;
        
    @(SdlSingularName("dependency"))
    string[string][] dependencies;
  }


  PackageInfo parsedPackage;

  void testParsePackage(bool copySdl, string sdlText, PackageInfo expectedPackage)
  {
    
    try {
      
      parseInto!PackageInfo(parsedPackage, setupSdlText(sdlText, copySdl));

    } catch(Exception e) {
      writefln("the following sdl threw an unexpected exception: %s", sdlText);
      writeln(e);
      assert(0);
    }

    if(expectedPackage != parsedPackage) {
      writefln("Expected: %s", expectedPackage);
      writefln(" but got: %s", parsedPackage);
      assert(0);
    }

  }



  testParsePackage(false, `
name "vibe-d"
packageID 1023
randomBytes 1 2 3 4
`, PackageInfo());
}