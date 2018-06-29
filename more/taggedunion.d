module more.taggedunion;

struct Tag
{
    string name;
    template opDispatch(string name)
    {
        enum opDispatch = Tag(name);
    }
}
mixin template TaggedUnion(T...)
{
    import std.conv : to;
    private enum enumDefMixin =
        "private enum TagEnum {\n" ~ function() {
            string fields = "";
            foreach (item; T)
            {
                static if ( is(typeof(item) : Tag) )
                {
                    fields ~= "    " ~ item.name ~ ",\n";
                }
            }
            return fields;
        }() ~ "}\n";
    pragma(msg, enumDefMixin);
    mixin(enumDefMixin);

    private enum unionMixin =
        "union {\n" ~ function() {
            string result = "";
            static foreach (itemIndex; 0 .. T.length)
            {
                static if (itemIndex % 3 == 0)
                {
                }
                else static if (itemIndex % 3 == 1)
                {
                    static if ( !is(T[itemIndex] == void))
                    {
                        result ~= "        T[" ~ itemIndex.to!string ~ "] ";
                    }
                }
                else
                {
                   static if (T[itemIndex] !is null)
                   {
                        result ~= T[itemIndex] ~ ";\n";
                   }
                }
            }
            return result;
        }() ~ "}\n";
    pragma(msg, unionMixin);
    mixin(unionMixin);
    TagEnum tag;
}
unittest
{
    struct PassOrFail
    {
        mixin TaggedUnion!(
            Tag.pass, void, null,
            Tag.fail, int, "errorCode");
    }
    auto result = PassOrFail();
}
