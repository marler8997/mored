module more.path;

import std.path;

version(unittest_path) {
  import std.stdio;
  import core.stdc.stdlib : alloca;

  import more.common;
}

auto rtrimDirSeparators(inout(char)[] path) @safe pure nothrow @nogc
{
  if(path.length <= 0) return path;

  auto i = path.length - 1;
  while(true) {
    if(!isDirSeparator(path[i])) return path[0 .. i+1];
    if(i == 0) return path[0..0];
    i--;
  }
}

/**
   Returns the parent directory of the given file/directory.
   If there is no parent directory, it will return an empty string.
   This function will include the trailing slash only if it is the root directory.
   Note: This function does not allocate a new string, instead it will
   return a slice to the given path.
 */
inout(char)[] parentDir(inout(char)[] path) @safe pure nothrow @nogc
{
  return path[0..parentDirLength(path)];
}
/**
   Returns the length of the substring that is the parent directory
   of the given path.  If there is no parent directory, it will return 0.
   This function will include the trailing slash only if it is the root directory.
 */
size_t parentDirLength(inout(char)[] path) @safe pure nothrow @nogc
{
  path = rtrimDirSeparators(path);
  if (path.length <= 0) return 0;

  // i is pointing at a nonDirSeparator
  size_t i;
  for(i = path.length - 1; !isDirSeparator(path[i]); i--) {
    if(i == 0) return 0;
  }

  // i is pointing at a dirSeparator, Remove the trailing dir separators
  while(true) {
    if(i == 0) return 1; // Handles '/' or '\'
    i--;
    if(!isDirSeparator(path[i])) break;
  }

  // i+1 is pointing at a dir separator and i is pointing at a nonDirSeparator
  if(path[i] == ':') return i+2;
  return i+1;
}

version(unittest_path) unittest
{
  mixin(scopedTest!("parentDir function"));

  assert(parentDir(null) == null);
  assert(parentDir("") == "");
  assert(parentDir("/") == "");
  assert(parentDir("///") == "");

  assert(parentDir("a") == "");
  assert(parentDir("abc") == "");
  assert(parentDir("/a") == "/");
  assert(parentDir("///a") == "/");
  assert(parentDir("/abc") == "/");
  assert(parentDir("///abc") == "/");

  assert(parentDir("dir/") == "");
  assert(parentDir("dir///") == "");
  assert(parentDir("dir/a") == "dir");
  assert(parentDir("dir///a") == "dir");
  assert(parentDir("dir/abc") == "dir");
  assert(parentDir("dir///abc") == "dir");

  version (Windows) {
    assert(parentDir(`c:`) == "");

    assert(parentDir(`c:\`) == "");
    assert(parentDir(`c:/`) == "");

    assert(parentDir(`c:\\\`) == "");
    assert(parentDir(`c:///`) == "");

    assert(parentDir(`c:\a`) == `c:\`);
    assert(parentDir(`c:/a`) == `c:/`);

    assert(parentDir(`c:\\\a`) == `c:\`);
    assert(parentDir(`c:///a`) == `c:/`);

    assert(parentDir(`c:\abc`) == `c:\`);
    assert(parentDir(`c:/abc`) == `c:/`);

    assert(parentDir(`c:\\\abc`) == `c:\`);
    assert(parentDir(`c:///abc`) == `c:/`);
  }
}

struct ParentDirTraverser
{
  string path;
  @property empty() nothrow @nogc {
    return path.length <= 0;
  }
  @property string front() nothrow @nogc {
    return path;
  }
  @property popFront() nothrow @nogc {
    path = parentDir(path);
  }
}

version(unittest_path) unittest
{
  mixin(scopedTest!("ParentDirTraverser"));

  ParentDirTraverser traverser;

  traverser = ParentDirTraverser("");
  assert(traverser.empty);

  traverser = ParentDirTraverser("a");
  assert(!traverser.empty);
  assert(traverser.front == "a");
  traverser.popFront;
  assert(traverser.empty);

  traverser = ParentDirTraverser("/a");
  assert(!traverser.empty);
  assert(traverser.front == "/a");
  traverser.popFront;
  assert(!traverser.empty);
  assert(traverser.front == "/");
  traverser.popFront;
  assert(traverser.empty);

  traverser = ParentDirTraverser("/parent/child");
  assert(!traverser.empty);
  assert(traverser.front == "/parent/child");
  traverser.popFront;
  assert(!traverser.empty);
  assert(traverser.front == "/parent");
  traverser.popFront;
  assert(!traverser.empty);
  assert(traverser.front == "/");
  traverser.popFront;
  assert(traverser.empty);

  traverser = ParentDirTraverser("Z:/parent/child/grandchild");
  assert(!traverser.empty);
  assert(traverser.front == "Z:/parent/child/grandchild");
  traverser.popFront;
  assert(!traverser.empty);
  assert(traverser.front == "Z:/parent/child");
  traverser.popFront;
  assert(!traverser.empty);
  assert(traverser.front == "Z:/parent");
  traverser.popFront;
  assert(!traverser.empty);
  assert(traverser.front == "Z:/");
  traverser.popFront;
  assert(traverser.empty);
}


char[] normalizePath(bool useSlashes)(char[] path) @safe pure nothrow @nogc
{
  return path[0..normalizePathLength!(useSlashes)(path)];
}
/**
  Normalizes the given path using the following:
    1. removes duplicate slashes/backslashes
    2. removes '/./' strings
    3. replaces 'path/..' strings with 'path'
    4. replaces all slashes/backslashes with the dirSeparator
    5. removed trailing slashes if not a root directory
  This function modifies the given string 
  Returns: The length of the normalized path
 */
size_t normalizePathLength(bool useSlashes)(char[] path) @safe pure nothrow @nogc
{
  enum dirSeparator      = useSlashes ? '/' : '\\';
  enum otherDirSeparator = useSlashes ? '\\' : '/';

  // Normalize Dir Separators
  for(auto i = 0; i < path.length; i++) {
    auto c = path[i];
    if(c == otherDirSeparator) {
      path[i] = dirSeparator;
    }
  }

  return path.length;

  //  size_t i = 0;

/+
  while(true) {
    auto c = path[i];

    if(c == dirSeparator) {
      
    }

  }
+/
}


version(unittest_path) unittest
{
  mixin(scopedTest!("normalizePath function"));
  
  void testNormalizePath(bool useSlashes)(string testString, string expected, size_t testLine = __LINE__)
  {
    auto normalized = cast(char*)alloca(testString.length);
    normalized[0..testString.length] = testString;

    auto actual = normalizePath!useSlashes(normalized[0..testString.length]);
    if(actual != expected) {
      writefln("Expected: '%s'", expected);
      writefln("Actual  : '%s'", actual);
      assert(0);
    }
  }


  testNormalizePath!true("/", "/");
  testNormalizePath!true(`\`, "/");

  testNormalizePath!false("/", `\`);
  testNormalizePath!false(`\`, `\`);



}

/+
unittest
{
    assert (normalizePath("") is null);
    assert (normalizePath("foo") == "foo");

    version (Posix)
    {
        assert (normalizePath("/", "foo", "bar") == "/foo/bar");
        assert (normalizePath("foo", "bar", "baz") == "foo/bar/baz");
        assert (normalizePath("foo", "bar/baz") == "foo/bar/baz");
        assert (normalizePath("foo", "bar//baz///") == "foo/bar/baz");
        assert (normalizePath("/foo", "bar/baz") == "/foo/bar/baz");
        assert (normalizePath("/foo", "/bar/baz") == "/bar/baz");
        assert (normalizePath("/foo/..", "/bar/./baz") == "/bar/baz");
        assert (normalizePath("/foo/..", "bar/baz") == "/bar/baz");
        assert (normalizePath("/foo/../../", "bar/baz") == "/bar/baz");
        assert (normalizePath("/foo/bar", "../baz") == "/foo/baz");
        assert (normalizePath("/foo/bar", "../../baz") == "/baz");
        assert (normalizePath("/foo/bar", ".././/baz/..", "wee/") == "/foo/wee");
        assert (normalizePath("//foo/bar", "baz///wee") == "/foo/bar/baz/wee");
        static assert (normalizePath("/foo/..", "/bar/./baz") == "/bar/baz");
        // Examples in docs:
        assert (normalizePath("/foo", "bar/baz/") == "/foo/bar/baz");
        assert (normalizePath("/foo", "/bar/..", "baz") == "/baz");
        assert (normalizePath("foo/./bar", "../../", "../baz") == "../baz");
        assert (normalizePath("/foo/./bar", "../../baz") == "/baz");
    }
    else version (Windows)
    {
        assert (normalizePath(`\`, `foo`, `bar`) == `\foo\bar`);
        assert (normalizePath(`foo`, `bar`, `baz`) == `foo\bar\baz`);
        assert (normalizePath(`foo`, `bar\baz`) == `foo\bar\baz`);
        assert (normalizePath(`foo`, `bar\\baz\\\`) == `foo\bar\baz`);
        assert (normalizePath(`\foo`, `bar\baz`) == `\foo\bar\baz`);
        assert (normalizePath(`\foo`, `\bar\baz`) == `\bar\baz`);
        assert (normalizePath(`\foo\..`, `\bar\.\baz`) == `\bar\baz`);
        assert (normalizePath(`\foo\..`, `bar\baz`) == `\bar\baz`);
        assert (normalizePath(`\foo\..\..\`, `bar\baz`) == `\bar\baz`);
        assert (normalizePath(`\foo\bar`, `..\baz`) == `\foo\baz`);
        assert (normalizePath(`\foo\bar`, `../../baz`) == `\baz`);
        assert (normalizePath(`\foo\bar`, `..\.\/baz\..`, `wee\`) == `\foo\wee`);

        assert (normalizePath(`c:\`, `foo`, `bar`) == `c:\foo\bar`);
        assert (normalizePath(`c:foo`, `bar`, `baz`) == `c:foo\bar\baz`);
        assert (normalizePath(`c:foo`, `bar\baz`) == `c:foo\bar\baz`);
        assert (normalizePath(`c:foo`, `bar\\baz\\\`) == `c:foo\bar\baz`);
        assert (normalizePath(`c:\foo`, `bar\baz`) == `c:\foo\bar\baz`);
        assert (normalizePath(`c:\foo`, `\bar\baz`) == `c:\bar\baz`);
        assert (normalizePath(`c:\foo\..`, `\bar\.\baz`) == `c:\bar\baz`);
        assert (normalizePath(`c:\foo\..`, `bar\baz`) == `c:\bar\baz`);
        assert (normalizePath(`c:\foo\..\..\`, `bar\baz`) == `c:\bar\baz`);
        assert (normalizePath(`c:\foo\bar`, `..\baz`) == `c:\foo\baz`);
        assert (normalizePath(`c:\foo\bar`, `..\..\baz`) == `c:\baz`);
        assert (normalizePath(`c:\foo\bar`, `..\.\\baz\..`, `wee\`) == `c:\foo\wee`);

        assert (normalizePath(`\\server\share`, `foo`, `bar`) == `\\server\share\foo\bar`);
        assert (normalizePath(`\\server\share\`, `foo`, `bar`) == `\\server\share\foo\bar`);
        assert (normalizePath(`\\server\share\foo`, `bar\baz`) == `\\server\share\foo\bar\baz`);
        assert (normalizePath(`\\server\share\foo`, `\bar\baz`) == `\\server\share\bar\baz`);
        assert (normalizePath(`\\server\share\foo\..`, `\bar\.\baz`) == `\\server\share\bar\baz`);
        assert (normalizePath(`\\server\share\foo\..`, `bar\baz`) == `\\server\share\bar\baz`);
        assert (normalizePath(`\\server\share\foo\..\..\`, `bar\baz`) == `\\server\share\bar\baz`);
        assert (normalizePath(`\\server\share\foo\bar`, `..\baz`) == `\\server\share\foo\baz`);
        assert (normalizePath(`\\server\share\foo\bar`, `..\..\baz`) == `\\server\share\baz`);
        assert (normalizePath(`\\server\share\foo\bar`, `..\.\\baz\..`, `wee\`) == `\\server\share\foo\wee`);

        static assert (normalizePath(`\foo\..\..\`, `bar\baz`) == `\bar\baz`);

        // Examples in docs:
        assert (normalizePath(`c:\foo`, `bar\baz\`) == `c:\foo\bar\baz`);
        assert (normalizePath(`c:\foo`, `bar/..`) == `c:\foo`);
        assert (normalizePath(`\\server\share\foo`, `..\bar`) == `\\server\share\bar`);
    }
    else static assert (0);
}

unittest
{
    version (Posix)
    {
        // Trivial
        assert (normalizePath("").empty);
        assert (normalizePath("foo/bar") == "foo/bar");

        // Correct handling of leading slashes
        assert (normalizePath("/") == "/");
        assert (normalizePath("///") == "/");
        assert (normalizePath("////") == "/");
        assert (normalizePath("/foo/bar") == "/foo/bar");
        assert (normalizePath("//foo/bar") == "/foo/bar");
        assert (normalizePath("///foo/bar") == "/foo/bar");
        assert (normalizePath("////foo/bar") == "/foo/bar");

        // Correct handling of single-dot symbol (current directory)
        assert (normalizePath("/./foo") == "/foo");
        assert (normalizePath("/foo/./bar") == "/foo/bar");

        assert (normalizePath("./foo") == "foo");
        assert (normalizePath("././foo") == "foo");
        assert (normalizePath("foo/././bar") == "foo/bar");

        // Correct handling of double-dot symbol (previous directory)
        assert (normalizePath("/foo/../bar") == "/bar");
        assert (normalizePath("/foo/../../bar") == "/bar");
        assert (normalizePath("/../foo") == "/foo");
        assert (normalizePath("/../../foo") == "/foo");
        assert (normalizePath("/foo/..") == "/");
        assert (normalizePath("/foo/../..") == "/");

        assert (normalizePath("foo/../bar") == "bar");
        assert (normalizePath("foo/../../bar") == "../bar");
        assert (normalizePath("../foo") == "../foo");
        assert (normalizePath("../../foo") == "../../foo");
        assert (normalizePath("../foo/../bar") == "../bar");
        assert (normalizePath(".././../foo") == "../../foo");
        assert (normalizePath("foo/bar/..") == "foo");
        assert (normalizePath("/foo/../..") == "/");

        // The ultimate path
        assert (normalizePath("/foo/../bar//./../...///baz//") == "/.../baz");
        static assert (normalizePath("/foo/../bar//./../...///baz//") == "/.../baz");
    }
    else version (Windows)
    {
        // Trivial
        assert (normalizePath("").empty);
        assert (normalizePath(`foo\bar`) == `foo\bar`);
        assert (normalizePath("foo/bar") == `foo\bar`);

        // Correct handling of absolute paths
        assert (normalizePath("/") == `\`);
        assert (normalizePath(`\`) == `\`);
        assert (normalizePath(`\\\`) == `\`);
        assert (normalizePath(`\\\\`) == `\`);
        assert (normalizePath(`\foo\bar`) == `\foo\bar`);
        assert (normalizePath(`\\foo`) == `\\foo`);
        assert (normalizePath(`\\foo\\`) == `\\foo`);
        assert (normalizePath(`\\foo/bar`) == `\\foo\bar`);
        assert (normalizePath(`\\\foo\bar`) == `\foo\bar`);
        assert (normalizePath(`\\\\foo\bar`) == `\foo\bar`);
        assert (normalizePath(`c:\`) == `c:\`);
        assert (normalizePath(`c:\foo\bar`) == `c:\foo\bar`);
        assert (normalizePath(`c:\\foo\bar`) == `c:\foo\bar`);

        // Correct handling of single-dot symbol (current directory)
        assert (normalizePath(`\./foo`) == `\foo`);
        assert (normalizePath(`\foo/.\bar`) == `\foo\bar`);

        assert (normalizePath(`.\foo`) == `foo`);
        assert (normalizePath(`./.\foo`) == `foo`);
        assert (normalizePath(`foo\.\./bar`) == `foo\bar`);

        // Correct handling of double-dot symbol (previous directory)
        assert (normalizePath(`\foo\..\bar`) == `\bar`);
        assert (normalizePath(`\foo\../..\bar`) == `\bar`);
        assert (normalizePath(`\..\foo`) == `\foo`);
        assert (normalizePath(`\..\..\foo`) == `\foo`);
        assert (normalizePath(`\foo\..`) == `\`);
        assert (normalizePath(`\foo\../..`) == `\`);

        assert (normalizePath(`foo\..\bar`) == `bar`);
        assert (normalizePath(`foo\..\../bar`) == `..\bar`);
        assert (normalizePath(`..\foo`) == `..\foo`);
        assert (normalizePath(`..\..\foo`) == `..\..\foo`);
        assert (normalizePath(`..\foo\..\bar`) == `..\bar`);
        assert (normalizePath(`..\.\..\foo`) == `..\..\foo`);
        assert (normalizePath(`foo\bar\..`) == `foo`);
        assert (normalizePath(`\foo\..\..`) == `\`);
        assert (normalizePath(`c:\foo\..\..`) == `c:\`);

        // Correct handling of non-root path with drive specifier
        assert (normalizePath(`c:foo`) == `c:foo`);
        assert (normalizePath(`c:..\foo\.\..\bar`) == `c:..\bar`);

        // The ultimate path
        assert (normalizePath(`c:\foo\..\bar\\.\..\...\\\baz\\`) == `c:\...\baz`);
        static assert (normalizePath(`c:\foo\..\bar\\.\..\...\\\baz\\`) == `c:\...\baz`);
    }
    else static assert (false);
}

unittest
{
    // Test for issue 7397
    string[] ary = ["a", "b"];
    version (Posix)
    {
        assert (normalizePath(ary) == "a/b");
    }
    else version (Windows)
    {
        assert (normalizePath(ary) == `a\b`);
    }
}
+/







/+

void appendPath(char* output, const(char[]) path)
{
  *output = dirSeparator[0];
  output[1..1+path.length] = path;
}
void buildPath(char* output, string[] segments...)
{
    if (segments.empty) return null;
    
    size_t first;
    foreach(i, segment; segments) {
      if(!segment.empty) {
	first = i;
	goto BUILD;
      }
    }
    
    return;

 BUILD:
    auto firstSegment = segments[first];
    output[0..firstSegment.length] = firstSegment;
    size_t pos = firstSegment.length;;
    foreach (segment; segments[first+1..$]) {
        if (segment.empty) continue;
/+
	if (isRooted(segment)) {
	  version (Posix) {
	    pos = 0;
	  } else version (Windows) {
	      if (isAbsolute(segment)) {
		pos = 0; 
	      } else {
		pos = rootName(buf[0 .. pos]).length;
		if (pos > 0 && isDirSeparator(buf[pos-1])) --pos;
	      }
	    }
	}
+/
	if (!isDirSeparator(output[pos-1])) {
	  output[pos++] = dirSeparator[0];
        }
        output[pos .. pos + segment.length] = segment[];
        pos += segment.length;
    }
}
+/

