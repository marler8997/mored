module more.builder;

import core.stdc.string : memmove;

import std.typecons : Flag, Yes, No;
import std.traits : isSomeChar, hasMember;

alias StringBuilder(SizeExpander) = Builder!(char, SizeExpander);

struct Builder(T, Expander)
{
    static assert(hasMember!(Expander, "expand"), Expander.stringof~" does not have an expand function");

    T[] buffer;
    size_t dataLength;

    @property T[] data() const { return cast(T[])buffer[0..dataLength]; }
    @property T[] available() const { return cast(T[])buffer[dataLength..$]; }

    T* getRef(size_t index)
    {
        return &buffer[index];
    }

    void ensureCapacity(size_t capacityNeeded)
    {
        if(capacityNeeded > buffer.length)
        {
            this.buffer = Expander.expand!T(buffer, dataLength, capacityNeeded);
        }
    }
    void makeRoomFor(size_t newContentLength)
    {
        ensureCapacity(dataLength + newContentLength);
    }
    T* reserveOne(Flag!"initialize" initialize)
    {
        makeRoomFor(1);
        if(initialize)
        {
            buffer[dataLength] = T.init;
        }
        return &buffer[dataLength++];
    }
    void shrink(size_t newLength) in { assert(newLength < dataLength); } body
    {
        dataLength = newLength;
    }
    void shrinkIfSmaller(size_t newLength)
    {
        if(newLength < dataLength)
        {
            dataLength = newLength;
        }
    }

    static if(__traits(compiles, { T t1; const(T) t2; t1 = t2; }))
    {
        void append(const(T) newElement)
        {
            makeRoomFor(1);
            buffer[dataLength++] = newElement;
        }
        void append(const(T)[] newElements)
        {
            makeRoomFor(newElements.length);
            buffer[dataLength..dataLength+newElements.length] = newElements[];
            dataLength += newElements.length;
        }
    }
    else
    {
        void append(T newElement)
        {
            makeRoomFor(1);
            buffer[dataLength++] = newElement;
        }
        void append(T[] newElements)
        {
            makeRoomFor(newElements.length);
            buffer[dataLength..dataLength+newElements.length] = newElements[];
            dataLength += newElements.length;
        }
    }

    static if(isSomeChar!T)
    {
        void appendf(Args...)(const(char)[] fmt, Args args)
        {
            import std.format : formattedWrite;
            formattedWrite(&append, fmt, args);
        }
        // Only call if the data in this builder will not be modified
        string finalString()
        {
            return cast(string)buffer[0..dataLength];
        }
    }

    void removeAt(size_t index) in { assert(index < dataLength); } body
    {
        if(index < dataLength-1)
        {
            memmove(&buffer[index], &buffer[index+1], T.sizeof * (dataLength-(index+1)));
        }
        dataLength--;
    }
}

// Always expands the to a power of 2 of the initial size.
struct GCDoubler(uint initialSize)
{
    static T[] expand(T)(T[] array, size_t preserveSize, size_t neededSize)
        in { assert(array.length < neededSize); } body
    {
        size_t newSize = (array.length == 0) ? initialSize : array.length * 2;
        while(neededSize > newSize)
        {
            newSize *= 2;
        }
        // TODO: there might be a more efficient way to do this?
        array.length = newSize;
        return array;
    }
}

struct MallocDoubler(uint initialSize)
{
    static import core.stdc.stdlib;
    static import core.stdc.string;

    static T[] expand(T)(T[] array, size_t preserveSize, size_t neededSize)
        in { assert(array.length < neededSize); } body
    {
        size_t newSize = (array.length == 0) ? initialSize : array.length * 2;
        while(neededSize > newSize)
        {
            newSize *= 2;
        }
        auto newPtr = cast(T*)core.stdc.stdlib.malloc(T.sizeof*newSize);
        assert(newPtr, "malloc returned null");
        if(preserveSize > 0)
        {
            core.stdc.string.memcpy(newPtr, array.ptr, T.sizeof*preserveSize);
        }
        if(array.ptr)
        {
            core.stdc.stdlib.free(array.ptr);
        }
        return newPtr[0..newSize];
    }
}

unittest
{
    static import core.stdc.stdlib;

    {
        auto builder = Builder!(int, GCDoubler!100)();
        assert(builder.buffer is null);
        assert(builder.dataLength == 0);
        assert(builder.data is null);
        builder.append(1);
        assert(builder.data == [1]);
        builder.append(2);
        assert(builder.data == [1,2]);
    }
    {
        auto builder = Builder!(int, MallocDoubler!1)();
        assert(builder.buffer is null);
        assert(builder.dataLength == 0);
        assert(builder.data is null);
        builder.append(1);
        assert(builder.data == [1]);
        builder.append(2);
        assert(builder.data == [1,2]);
        builder.append(3);
        assert(builder.data == [1,2,3]);
        core.stdc.stdlib.free(builder.buffer.ptr);
    }

    struct BadExpander1
    {
        // no expand function
    }
    assert(!__traits(compiles, {auto builder = Builder!(int, BadExpander1);}));

    struct BadExpander2
    {
        // invalid expand function
        static void expand()
        {
        }
    }
    assert(!__traits(compiles, {auto builder = Builder!(int, BadExpander2);}));
}
