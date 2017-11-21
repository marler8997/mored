module more.parse;

// returns: ubyte.max on error
ubyte hexValue(char c)
{
    if(c <= '9') {
        return (c >= '0') ? cast(ubyte)(c - '0') : ubyte.max;
    }
    if(c >= 'a') {
        return (c <= 'f') ? cast(ubyte)(c + 10 - 'a') : ubyte.max;
    }
    if(c >= 'A' && c <= 'F') {
        return cast(ubyte)(c + 10 - 'A');
    }
    return ubyte.max;
}
unittest
{
    assert(ubyte.max == hexValue('/'));
    assert(0 == hexValue('0'));
    assert(9 == hexValue('9'));
    assert(ubyte.max == hexValue(':'));

    assert(ubyte.max == hexValue('@'));
    assert(10 == hexValue('A'));
    assert(15 == hexValue('F'));
    assert(ubyte.max == hexValue('G'));

    assert(ubyte.max == hexValue('`'));
    assert(10 == hexValue('a'));
    assert(15 == hexValue('f'));
    assert(ubyte.max == hexValue('g'));

    for(int cAsInt = char.min; cAsInt <= char.max; cAsInt++) {
        char c = cast(char)cAsInt;
        if(c >= '0' && c <= '9') {
            assert(c - '0' == hexValue(c));
        } else if(c >= 'a' && c <= 'f') {
            assert(c + 10 - 'a' == hexValue(c));
        } else if(c >= 'A' && c <= 'F') {
            assert(c + 10 - 'A' == hexValue(c));
        } else {
            assert(ubyte.max == hexValue(c));
        }
    }
}

/**
Iterates over the given string and returns a pointer to the first character that
is not in the given $(D charSet).
*/
inout(char)* skipCharSet(string charSet)(inout(char)* str)
{
  STR_LOOP:
    for(;;)
    {
        auto c = *str;
        foreach(charSetChar; charSet) {
            if(c == charSetChar) {
                str++;
                continue STR_LOOP;
            }
        }
        break;
    }
    return str;
}
/// ditto
inout(char)* skipCharSet(string charSet)(inout(char)* str, const(char)* limit)
{
  STR_LOOP:
    for(;str < limit;)
    {
        auto c = *str;
        foreach(charSetChar; charSet) {
            if(c == charSetChar) {
                str++;
                continue STR_LOOP;
            }
        }
        break;
    }
    return str;
}
/**
Iterates over the given string and returns a pointer to the first character that
is not a space.
*/
pragma(inline) inout(char)* skipSpace(inout(char)* str)
{
    return skipCharSet!" "(str);
}
pragma(inline) inout(char)* skipSpace(inout(char)* str, const(char)* limit)
{
    return skipCharSet!" "(str, limit);
}

// TODO: create more overloads
bool startsWith(const(char)* str, const(char)* limit, const(char)[] needle)
{
    auto size = limit - str;
    if(size < needle.length)
    {
        return false;
    }
    return str[0..needle.length] == needle[];
}

/** Returns a pointer to the first occurence of $(D c) or $(D sentinal).
*/
inout(char)* findCharPtr(char sentinal = '\0')(inout(char)* str, char c)
{
    for(;;str++) {
        if(*str == c || *str == sentinal) {
            return str;
        }
    }
}
/** Returns a pointer to the first occurence of $(D c).  If no $(D c) is found
    then the limit is returned.
 */
inout(char)* findCharPtr(inout(char)* str, const(char)* limit, char c)
{
    for(;;str++) {
        if(str >= limit || *str == c) {
           return str;
        }
    }
}
/// ditto
pragma(inline)
inout(char)* findCharPtr(inout(char)[] str, char c)
{
    return findCharPtr(str.ptr, str.ptr + str.length, c);
}

/** Returns the index of the first occurence of $(D c).  If no $(D c) is found
    then the length of the string is returned.
 */
size_t findCharIndex(char sentinal = '\0')(const(char)* str, char c)
{
    auto saveStart = str;
    for(;;str++) {
        if(*str == c || *str == sentinal) {
            return str - saveStart;
        }
    }
}
size_t findCharIndex(const(char)* str, const(char)* limit, char c)
{
    auto saveStart = str;
    for(;;str++) {
        if(str >= limit || *str == c) {
           return str - saveStart;
        }
    }
}
size_t findCharIndex(const(char)[] str, char c)
{
    foreach(i, strChar; str) {
        if(c == strChar) {
            return i;
        }
    }
    return str.length;
}