/**
Contains types to differentiate arrays with sentinel values.
*/
module more.sentinel;

/**
Selects the default sentinel value for a type `T`.

It has a special case for the char types, and also allows
the type to define its own default sentinel value if it
has the member `defaultSentinel`. Otherwise, it uses `T.init`.
*/
private template defaultSentinel(T)
{
         static if (is(Unqual!T ==  char)) enum defaultSentinel = '\0';
    else static if (is(Unqual!T == wchar)) enum defaultSentinel = cast(wchar)'\0';
    else static if (is(Unqual!T == dchar)) enum defaultSentinel = cast(dchar)'\0';
    else static if (__traits(hasMember, T, "defaultSentinel")) enum defaultSentinel = T.defaultSentinel;
    else                                   enum defaultSentinel = T.init;
}

// NOTE: T should be unqalified (not const/immutable etc)
//       This "unqualification" of T is done by the `SentinelPtr` and `SentinelArray` templates.
private template SentinelTemplate(T, immutable T sentinelValue)
{
    private enum CommonPtrMembers = q{
        static auto nullPtr() { return typeof(this)(null); }

        /**
        Interpret a raw pointer `ptr` as a `SentinelPtr` without checking that
        the array it is pointing to has a sentinel value.
        Params:
            ptr = the raw pointer to be converted
        Returns:
            the given `ptr` interpreted as a `SentinelPtr`
        */
        static auto assume(SpecificT* ptr) pure
        {
            return typeof(this)(ptr);
        }

        SpecificT* ptr;
        private this(SpecificT* ptr) { this.ptr = ptr; }
        this(typeof(this) other) { this.ptr = other.ptr; }

        pragma(inline) ConstPtr asConst() inout { return ConstPtr(cast(const(T)*)ptr); }

        /**
        Converts the ptr to an array by "walking" it for the sentinel value to determine its length.

        Returns:
            the ptr as a SentinelArray
        */
        SentinelArray walkToArray() inout
        {
            return SentinelArray((cast(SpecificT*)ptr)[0 .. walkLength()]);
        }

        /**
        Return the current value pointed to by `ptr`.
        */
        auto front() inout { return *ptr; }

        /**
        Move ptr to the next value.
        */
        void popFront() { ptr++; }
    };
    struct MutablePtr
    {
        private alias SpecificT = T;
        private alias SentinelArray = MutableArray;

        mixin(CommonPtrMembers);

        alias asConst this; // facilitates implicit conversion to const type
        // alias ptr this; // NEED MULTIPLE ALIAS THIS!!!
    }
    struct ImmutablePtr
    {
        private alias SpecificT = immutable(T);
        private alias SentinelArray = ImmutableArray;

        mixin(CommonPtrMembers);
        alias asConst this; // facilitates implicit conversion to const type
        // alias ptr this; // NEED MULTIPLE ALIAS THIS!!!
    }
    struct ConstPtr
    {
        private alias SpecificT = const(T);
        private alias SentinelArray = ConstArray;

        mixin(CommonPtrMembers);
        alias ptr this;

        /**
        Returns true if `ptr` is pointing at the sentinel value.
        */
        @property bool empty() const { return *this == sentinelValue; }

        /**
        Walks the array to determine its length.
        Returns:
            the length of the array
        */
        size_t walkLength() const
        {
            for(size_t i = 0; ; i++)
            {
                if (ptr[i] == sentinelValue)
                {
                    return i;
                }
            }
        }
    }

    private enum CommonArrayMembers = q{
        /**
        Interpret `array` as a `SentinalArray` without checking that
        the array it is pointing to has a sentinel value.
        Params:
            ptr = the raw pointer to be converted
        Returns:
            the given `ptr` interpreted as a `SentinelPtr`
        */
        static auto assume(SpecificT[] array) pure
        {
            return typeof(this)(array);
        }

        /**
        Interpret `array`` as a `SentinalArray` checking that the array it
        is pointing to ends with a sentinel value.
        Params:
            ptr = the raw pointer to be converted
        Returns:
            the given `ptr` interpreted as a `SentinelPtr`
        */
        static auto verify(SpecificT[] array) pure
        in { assert(array.ptr[array.length] == sentinelValue, "array does not end with sentinel value"); } do
        {
            return typeof(this)(array);
        }

        SpecificT[] array;
        private this(SpecificT[] array) { this.array = array; }
        this(typeof(this) other) { this.array = other.array; }

        pragma(inline) SentinelPtr ptr() const { return SentinelPtr(cast(SpecificT*)array.ptr); }

        pragma(inline) ConstArray asConst() inout { return ConstArray(cast(const(T)[])array); }

        /**
        A no-op that just returns the array as is.  This is to be useful for templates that can accept
        normal arrays an sentinel arrays. The function is marked as `@system` not because it is unsafe
        but because it should only be called in unsafe code, mirroring the interface of the free function
        version of asSentinelArray.

        Returns:
            this
        */
        pragma(inline) auto asSentinelArray() @system inout { return this; }
        /// ditto
        pragma(inline) auto asSentinelArrayUnchecked() @system inout { return this; }
    };
    struct MutableArray
    {
        private alias SpecificT = T;
        private alias SentinelPtr = MutablePtr;

        mixin(CommonArrayMembers);
        alias asConst this; // facilitates implicit conversion to const type
        // alias array this; // NEED MULTIPLE ALIAS THIS!!!

        /**
        Coerce the given `array` to a `SentinelArray`. It checks and asserts
        if the given array does not contain the sentinel value at `array.ptr[array.length]`.
        */
        this(T[] array) @system
        in { assert(array.ptr[array.length] == sentinelValue,
            "array does not end with sentinel value"); } do
        {
            this.array = array;
        }
    }
    struct ImmutableArray
    {
        private alias SpecificT = immutable(T);
        private alias SentinelPtr = ImmutablePtr;

        mixin(CommonArrayMembers);
        alias asConst this; // facilitates implicit conversion to const type
        // alias array this; // NEED MULTIPLE ALIAS THIS!!!

        /**
        Coerce the given `array` to a `SentinelArray`. It checks and asserts
        if the given array does not contain the sentinel value at `array.ptr[array.length]`.
        */
        this(immutable(T)[] array) @system
        in { assert(array.ptr[array.length] == sentinelValue,
            "array does not end with sentinel value"); } do
        {
            this.array = array;
        }
    }
    struct ConstArray
    {
        private alias SpecificT = const(T);
        private alias SentinelPtr = ConstPtr;

        mixin(CommonArrayMembers);
        alias array this;

        bool opEquals(const(T)[] other) const
        {
            return array == other;
        }
    }
}

/**
A pointer to an array with a sentinel value.
*/
template SentinelPtr(T, T sentinelValue = defaultSentinel!T)
{
         static if (is(T U ==     const U)) alias SentinelPtr = SentinelTemplate!(U, sentinelValue).ConstPtr;
    else static if (is(T U == immutable U)) alias SentinelPtr = SentinelTemplate!(U, sentinelValue).ImmutablePtr;
    else                                    alias SentinelPtr = SentinelTemplate!(T, sentinelValue).MutablePtr;
}
/**
An array with the extra requirement that it ends with a sentinel value at `ptr[length]`.
*/
template SentinelArray(T, T sentinelValue = defaultSentinel!T)
{
         static if (is(T U ==     const U)) alias SentinelArray = SentinelTemplate!(U, sentinelValue).ConstArray;
    else static if (is(T U == immutable U)) alias SentinelArray = SentinelTemplate!(U, sentinelValue).ImmutableArray;
    else                                    alias SentinelArray = SentinelTemplate!(T, sentinelValue).MutableArray;
}

/**
Create a SentinelPtr from a normal pointer without checking
that the array it is pointing to contains the sentinel value.
*/
@property auto assumeSentinel(T)(T* ptr) @system
{
    return SentinelPtr!T.assume(ptr);
}
@property auto assumeSentinel(alias sentinelValue, T)(T* ptr) @system
    if (is(typeof(sentinelValue) == typeof(T.init)))
{
    return SentinelPtr!(T, sentinelValue).assume(ptr);
}

/**
Coerce the given `array` to a `SentinelPtr`. It checks and asserts
if the given array does not contain the sentinel value at `array.ptr[array.length]`.
*/
@property auto verifySentinel(T)(T[] array) @system
{
    return SentinelArray!T.verify(array);
}
/// ditto
@property auto verifySentinel(alias sentinelValue, T)(T[] array) @system
    if (is(typeof(sentinelValue == T.init)))
{
    return SentinelArray!(T, sentinelValue).verify(array);
}

/**
Coerce the given `array` to a `SentinelArray` without verifying that it
contains the sentinel value at `array.ptr[array.length]`.
*/
@property auto assumeSentinel(T)(T[] array) @system
{
    return SentinelArray!T.assume(array);
}
@property auto assumeSentinel(alias sentinelValue, T)(T[] array) @system
    if (is(typeof(sentinelValue == T.init)))
{
    return SentinelArray!(T, sentinelValue).assume(array);
}
unittest
{
    auto s1 = "abcd".verifySentinel;
    auto s2 = "abcd".assumeSentinel;
    auto s3 = "abcd".ptr.assumeSentinel;

    auto full = "abcd-";
    auto s = full[0..4];
    auto s4 = s.verifySentinel!'-';
    auto s5 = s.assumeSentinel!'-';
}
unittest
{
    auto s1 = "abcd".verifySentinel;
    auto s2 = "abcd".assumeSentinel;

    auto full = "abcd-";
    auto s = full[0..4];
    auto s3 = s.verifySentinel!'-';
    auto s4 = s.assumeSentinel!'-';
}

// test as ranges
unittest
{
    {
        auto s = "abcd".verifySentinel;
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 4);
    }
    {
        auto s = "abcd".verifySentinel;
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 4);
    }
    auto abcd = "abcd";
    {
        auto s = abcd[0..3].verifySentinel!'d'.ptr;
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 3);
    }
    {
        auto s = abcd[0..3].verifySentinel!'d'.ptr;
        size_t count = 0;
        foreach(c; s) { count++; }
        assert(count == 3);
    }
}

unittest
{
    auto p1 = "hello".verifySentinel.ptr;
    auto p2 = "hello".assumeSentinel.ptr;
    assert(p1.walkLength() == 5);
    assert(p2.walkLength() == 5);

    assert(p1.walkToArray() == "hello");
    assert(p2.walkToArray() == "hello");
}

// Check that sentinel types can be passed to functions
// with mutable/immutable implicitly converting to const
unittest
{
    import more.c : cstring;

    static void immutableFooString(SentinelString str) { }
    immutableFooString("hello".verifySentinel);
    immutableFooString(StringLiteral!"hello");
    // NOTE: this only works if type of string literals is changed to SentinelString
    //immutableFooString("hello");

    static void mutableFooArray(SentinelArray!char str) { }
    mutableFooArray((cast(char[])"hello").verifySentinel);

    static void constFooArray(SentinelArray!(const(char)) str) { }
    constFooArray("hello".verifySentinel);
    constFooArray(StringLiteral!"hello");
    constFooArray((cast(const(char)[])"hello").verifySentinel);
    constFooArray((cast(char[])"hello").verifySentinel);

    // NOTE: this only works if type of string literals is changed to SentinelString
    //constFooArray("hello");

    static void immutableFooCString(cstring str) { }
    immutableFooCString("hello".verifySentinel.ptr);
    immutableFooCString(StringLiteral!"hello".ptr);

    static void mutableFooPtr(SentinelPtr!char str) { }
    mutableFooPtr((cast(char[])"hello").verifySentinel.ptr);

    static void fooPtr(cstring str) { }
    fooPtr("hello".verifySentinel.ptr);
    fooPtr(StringLiteral!"hello".ptr);
    fooPtr((cast(const(char)[])"hello").verifySentinel.ptr);
    fooPtr((cast(char[])"hello").verifySentinel.ptr);
}

// Check that sentinel array/ptr implicitly convert to non-sentinel array/ptr
unittest
{
    static void mutableFooArray(char[] str) { }
    // NEED MULTIPLE ALIAS THIS !!!
    //mutableFooArray((cast(char[])"hello").verifySentinel);

    static void immutableFooArray(string str) { }
    // NEED MULTIPLE ALIAS THIS !!!
    //immutableFooArray("hello".verifySentinel);
    //immutableFooArray(StringLiteral!"hello");

    static void constFooArray(const(char)[] str) { }
    constFooArray((cast(char[])"hello").verifySentinel);
    constFooArray((cast(const(char)[])"hello").verifySentinel);
    constFooArray("hello".verifySentinel);
    constFooArray(StringLiteral!"hello");

    static void mutableFooPtr(char* str) { }
    // NEED MULTIPLE ALIAS THIS !!!
    //mutableFooPtr((cast(char[])"hello").verifySentinel.ptr);

    static void immutableFooPtr(immutable(char)* str) { }
    // NEED MULTIPLE ALIAS THIS !!!
    //immutableFooPtr("hello".verifySentinel.ptr);
    //immutableFooPtr(StringLiteral!"hello");

    static void constFooPtr(const(char)* str) { }
    constFooPtr((cast(char[])"hello").verifySentinel.ptr);
    constFooPtr((cast(const(char)[])"hello").verifySentinel.ptr);
    constFooPtr("hello".verifySentinel.ptr);
    constFooPtr(StringLiteral!"hello".ptr);
}

/**
An array of characters that contains a null-terminator at the `length` index.

NOTE: the type of string literals could be changed to SentinelString
*/
alias SentinelString = SentinelArray!(immutable(char));
alias SentinelWstring = SentinelArray!(immutable(wchar));
alias SentinelDstring = SentinelArray!(immutable(dchar));

unittest
{
    {
        auto s1 = "hello".verifySentinel;
        auto s2 = "hello".assumeSentinel;
    }
    {
        SentinelString s = "hello";
    }
}

/**
A template that coerces a string literal to a SentinelString.
Note that this template becomes unnecessary if the type of string literal
is changed to SentinelString.
*/
pragma(inline) @property SentinelString StringLiteral(string s)() @trusted
{
   SentinelString ss = void;
   ss.array = s;
   return ss;
}
/// ditto
pragma(inline) @property SentinelWstring StringLiteral(wstring s)() @trusted
{
   SentinelWstring ss = void;
   ss.array = s;
   return ss;
}
/// ditto
pragma(inline) @property SentinelDstring StringLiteral(dstring s)() @trusted
{
   SentinelDstring ss = void;
   ss.array = s;
   return ss;
}

unittest
{
    // just instantiate for now to make sure they compile
    auto sc = StringLiteral!"hello";
    auto sw = StringLiteral!"hello"w;
    auto sd = StringLiteral!"hello"d;
}

/**
This function converts an array to a SentinelArray.  It requires that the last element `array[$-1]`
be equal to the sentinel value. This differs from the function `asSentinelArray` which requires
the first value outside of the bounds of the array `array[$]` to be equal to the sentinel value.
This function does not require the array to "own" elements outside of its bounds.
*/
@property auto reduceSentinel(T)(T[] array) @trusted
in {
    assert(array.length > 0);
    assert(array[$ - 1] == defaultSentinel!T);
   } do
{
    return array[0 .. $-1].assumeSentinel;
}
/// ditto
@property auto reduceSentinel(alias sentinelValue, T)(T[] array) @trusted
    if (is(typeof(sentinelValue == T.init)))
    in {
        assert(array.length > 0);
        assert(array[$ - 1] == sentinelValue);
    } do
{
    return array[0 .. $ - 1].assumeSentinel!sentinelValue;
}

///
@safe unittest
{
    auto s1 = "abc\0".reduceSentinel;
    assert(s1.length == 3);
    () @trusted {
        assert(s1.ptr[s1.length] == '\0');
    }();

    auto s2 = "foobar-".reduceSentinel!'-';
    assert(s2.length == 6);
    () @trusted {
        assert(s2.ptr[s2.length] == '-');
    }();
}

// poor mans Unqual
private template Unqual(T)
{
         static if (is(T U ==     const U)) alias Unqual = U;
    else static if (is(T U == immutable U)) alias Unqual = U;
    else                                    alias Unqual = T;
}
