module more.array;

import std.format : format;

template isArrayLike(T)
{
    enum isArrayLike =
           is(typeof(T.init.length))
        && is(typeof(T.init.ptr))
        && is(typeof(T.init[0]));
}

/**
TODO move this to mored
*/
pragma(inline) void copyFrom(T,U)(T dst, U src)
if (isArrayLike!T && isArrayLike!U && dst[0].sizeof == src[0].sizeof)
{
    assert(dst.length >= src.length, "copyFrom source length larger than destination");
    import core.stdc.string : memcpy;
    memcpy(dst.ptr, src.ptr, src.length);
}

pragma(inline) void setBytes(T,U)(T dst, U value)
if (isArrayLike!T && T.init[0].sizeof == 1 && value.sizeof == 1)
{
    import core.stdc.string : memset;
    memset(dst.ptr, cast(int)value, dst.length);
}


/**
TODO: move this to the mored repository

A LimitArray is like an array, except it contains 2 pointers, "ptr" and "limit",
instead of a "ptr" and "length".

The first pointer, "ptr", points to the beginning (like a normal array) and the
second pointer, "limit", points to 1 element past the last element in the array.

```
-------------------------------
| first | second | ... | last |
-------------------------------
 ^                             ^
 ptr                           limit
````

To get the length of the LimitArray, you can evaluate `limit - ptr`.
To check if a LimitArray is empty, you can check if `ptr == limit`.

The reason for the existense of the LimitArray structure is that some functionality
is more efficient when it uses this representation.  A common example is when processing
or parsing an array of elements where the beginning is iteratively "sliced off" as
it is being processed, i.e.  array = array[someCount .. $];  This operation is more efficient
when using a LimitArray because only the "ptr" field needs to be modified whereas a normal array
needs to modify the "ptr" field and the "length" each time. Note that other operations are more
efficiently done using a normal array, for example, if the length needs to be evaluated quite
often then it might make more sense to use a normal array.

In order to support "Element Type Modifiers" on a LimitArray's pointer types, the types are
defined using a template. Here is a table of LimitArray types with their equivalent normal array types.

| Normal Array        | Limit Array             |
|---------------------|-------------------------|
| `char[]`            | `LimitArray!char.mutable` `LimitArray!(const(char)).mutable` `LimitArray!(immutable(char)).mutable` |
| `const(char)[]`     | `LimitArray!char.const` `LimitArray!(const(char)).const` `LimitArray!(immutable(char)).const` |
| `immutable(char)[]` | `LimitArray!char.immutable` `LimitArray!(const(char)).immutable` `LimitArray!(immutable(char)).immutable` |

*/
template LimitArray(T)
{
    static if( !is(T == Unqual!T) )
    {
        alias LimitArray = LimitArray!(Unqual!T);
    }
    else
    {
        enum CommonMixin = q{
            pragma(inline) @property auto asArray()
            {
                return this.ptr[0 .. limit - ptr];
            }
            pragma(inline) auto slice(size_t offset)
            {
                auto newPtr = ptr + offset;
                assert(newPtr <= limit, "slice offset range violation");
                return typeof(this)(newPtr, limit);
            }
            pragma(inline) auto slice(size_t offset, size_t newLimit)
                in { assert(newLimit >= offset, "slice offset range violation"); } do
            {
                auto newLimitPtr = ptr + newLimit;
                assert(newLimitPtr <= limit, "slice limit range violation");
                return typeof(this)(ptr + offset, ptr + newLimit);
            }
            pragma(inline) auto ptrSlice(typeof(this.ptr) ptr)
            {
                auto copy = this;
                copy.ptr = ptr;
                return copy;
            }
        };

        struct mutable
        {
            union
            {
                struct
                {
                    T* ptr;
                    T* limit;
                }
                const_ constVersion;
            }
            // mutable is implicitly convertible to const
            alias constVersion this;

            mixin(CommonMixin);
        }
        struct immutable_
        {
            union
            {
                struct
                {
                    immutable(T)* ptr;
                    immutable(T)* limit;
                }
                const_ constVersion;
            }
            // immutable is implicitly convertible to const
            alias constVersion this;

            mixin(CommonMixin);
        }
        struct const_
        {
            const(T)* ptr;
            const(T)* limit;
            mixin(CommonMixin);
            auto startsWith(const(T)[] check) const
            {
                return ptr + check.length <= limit &&
                    0 == memcmp(ptr, check.ptr, check.length);
            }
            auto equals(const(T)[] check) const
            {
                return ptr + check.length == limit &&
                    0 == memcmp(ptr, check.ptr, check.length);
            }
        }
    }
}

pragma(inline)
@property auto asLimitArray(T)(T[] array)
{
    static if( is(T == immutable) )
    {
        return LimitArray!T.immutable_(array.ptr, array.ptr + array.length);
    }
    else static if( is(T == const) )
    {
        return LimitArray!T.const_(array.ptr, array.ptr + array.length);
    }
    else
    {
        return LimitArray!T.mutable(array.ptr, array.ptr + array.length);
    }
}

/**
TODO: move this to the mored repo

An array type that uses a custom type for the length.
*/
struct LengthArray(T, SizeType)
{
    @property static typeof(this) nullValue() { return typeof(this)(null, 0); }

    T* ptr;
    SizeType length;

    void nullify() { this.ptr = null; this.length = 0; }
    bool isNull() const { return ptr is null; }

    pragma(inline) @property auto ref last() const
        in { assert(length > 0); } do { return ptr[length - 1]; }

    pragma(inline) auto ref opIndex(SizeType index) inout
        in { assert(index < length, format("range violation %s >= %s", index, length)); } do
    {
        return ptr[index];
    }
    static if (size_t.sizeof != SizeType.sizeof)
    {
        pragma(inline) auto ref opIndex(size_t index) inout
            in { assert(index < length, format("range violation %s >= %s", index, length)); } do
        {
            return ptr[index];
        }
    }
    pragma(inline) SizeType opDollar() const
    {
        return length;
    }
    /*
    pragma(inline) auto ref opSlice(SizeType start, SizeType limit) inout
        in { assert(limit >= start, "slice range violation"); } do
    {
        return inout LengthArray!(T,SizeType)(ptr + start, cast(SizeType)(limit - start));
    }
    */
    pragma(inline) auto ref opSlice(SizeType start, SizeType limit)
        in { assert(limit >= start, "slice range violation"); } do
    {
        return LengthArray!(T,SizeType)(ptr + start, cast(SizeType)(limit - start));
    }

    pragma(inline) int opApply(scope int delegate(ref T element) dg) const
    {
        int result = 0;
        for (SizeType i = 0; i < length; i++)
        {
            result = dg(*cast(T*)&ptr[i]);
            if (result)
                break;
        }
        return result;
    }
    pragma(inline) int opApply(scope int delegate(SizeType index, ref T element) dg) const
    {
        int result = 0;
        for (SizeType i = 0; i < length; i++)
        {
            result = dg(i, *cast(T*)&ptr[i]);
            if (result)
                break;
        }
        return result;
    }

    @property auto asArray() { return ptr[0..length]; }
    //alias toArray this;

    /*
    // range functions
    @property bool empty() { return length == 0; }
    @property auto front() { return *ptr; }
    void popFront() {
        ptr++;
        length--;
    }
    */
}
pragma(inline) LengthArray!(T, LengthType) asLengthArray(LengthType, T)(T[] array)
in {
    static if (LengthType.sizeof < array.length.sizeof)
    {
        assert(array.length <= LengthType.max,
            format("array length %s exceeded " ~ LengthType.stringof ~ ".max %s", array.length, LengthType.max));
    }
} do
{
    return LengthArray!(T, LengthType)(array.ptr, cast(LengthType)array.length);
}

pragma(inline) LengthArray!(T, LengthType) asLengthArray(LengthType, T)(T* ptr, LengthType length)
{
    return LengthArray!(T, LengthType)(ptr, length);
}


