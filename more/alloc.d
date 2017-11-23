module more.alloc;

static import core.stdc.stdlib;
static import core.stdc.string;

import std.typecons : Flag, Yes, No;

T* cmalloc(T)(Flag!"zero" zero = Yes.zero)
{
    void* mem = core.stdc.stdlib.malloc(T.sizeof);
    assert(mem, "out of memory");
    if(zero)
    {
        core.stdc.string.memset(mem, 0, T.sizeof);
    }
    return cast(T*)mem;
}
T[] cmallocArray(T)(size_t size, Flag!"zero" zero = Yes.zero)
{
    void* mem = core.stdc.stdlib.malloc(T.sizeof * size);
    assert(mem, "out of memory");
    if(zero)
    {
        core.stdc.string.memset(mem, 0, T.sizeof * size);
    }
    return (cast(T*)mem)[0..size];
}
void cfree(T)(T* mem)
{
    core.stdc.stdlib.free(mem);
}



struct Mem
{
    void* ptr;
    size_t size;
}

// Always expands the memory to a power of 2 of the initial size.
struct GCDoubler(uint initialSize)
{
    private static auto getSize(size_t currentSize, size_t requestedSize)
    {
        size_t size = (currentSize == 0) ? initialSize : currentSize * 2;
        while(requestedSize > size)
        {
            size *= 2;
        }
        return size;
    }

    static T[] expand(T)(T[] array, size_t preserveSize, size_t neededSize)
        in { assert(array.length < neededSize); } body
    {
        // TODO: there might be a more efficient way to do this?
        array.length = getSize(array.length, neededSize);
        return array;
    }

    static Mem alloc(Mem current, size_t newRequestedSize)
    {
        import core.memory : GC;
        auto newSize = getSize(current.size, newRequestedSize);
        return Mem(GC.malloc(newSize), newSize);
    }
    static Mem alloc(Mem current, size_t newRequestedSize, size_t copyOffset, size_t copyLimit)
    {
        import core.memory : GC;
        auto newSize = getSize(current.size, newRequestedSize);
        auto newMem = GC.malloc(newSize);
        (cast(ubyte*)newMem)[copyOffset..copyLimit] = (cast(ubyte*)current.ptr)[copyOffset..copyLimit];
        return Mem(newMem, newSize);
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