module more.alloc;

static import core.stdc.stdlib;
static import core.stdc.string;

import std.typecons : Flag, Yes, No;

T* cmalloc(T)(Flag!"zero" zero = Yes.zero)
{
  void* mem = core.stdc.stdlib.malloc(T.sizeof);
  assert(mem, "out of memory");
  if(zero) {
    core.stdc.string.memset(mem, 0, T.sizeof);
  }
  return cast(T*)mem;
}
T[] cmallocArray(T)(size_t size, Flag!"zero" zero = Yes.zero)
{
  void* mem = core.stdc.stdlib.malloc(T.sizeof * size);
  assert(mem, "out of memory");
  if(zero) {
    core.stdc.string.memset(mem, 0, T.sizeof * size);
  }
  return (cast(T*)mem)[0..size];
}
void cfree(T)(T* mem)
{
  core.stdc.stdlib.free(mem);
}

