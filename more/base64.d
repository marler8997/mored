module more.base64;

immutable encode64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
auto formatBase64(T, size_t StackSize = 100)(const(T)[] data) if(T.sizeof == 1)
{
    static struct Formatter
    {
        const(T)[] data;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            ubyte stackIndex = 0;
            size_t dataIndex = 0;
            char[StackSize] stackBuffer;

            for(; dataIndex + 2 < data.length; dataIndex += 3)
            {
                stackBuffer[stackIndex++] = encode64[        (data[dataIndex + 0] >> 2                           ) ];
                stackBuffer[stackIndex++] = encode64[ 0x3F & (data[dataIndex + 0] << 4 | data[dataIndex + 1] >> 4) ];
                stackBuffer[stackIndex++] = encode64[ 0x3F & (data[dataIndex + 1] << 2 | data[dataIndex + 2] >> 6) ];
                stackBuffer[stackIndex++] = encode64[ 0x3F & (data[dataIndex + 2]                                ) ];
                if(stackIndex + 3 >= stackBuffer.length)
                {
                    sink(stackBuffer[0..stackIndex]);
                    stackIndex = 0;
                }
            }

            if(dataIndex < data.length)
            {
                stackBuffer[stackIndex++] = encode64[        (data[dataIndex + 0] >> 2                           ) ];
                if(dataIndex + 1 >= data.length)
                {
                    stackBuffer[stackIndex++] = encode64[ 0x3F & (data[dataIndex + 0] << 4                           ) ];
                    stackBuffer[stackIndex++] = '=';
                    stackBuffer[stackIndex++] = '=';
                }
                else
                {
                    stackBuffer[stackIndex++] = encode64[ 0x3F & (data[dataIndex + 0] << 4 | data[dataIndex + 1] >> 4) ];
                    stackBuffer[stackIndex++] = encode64[ 0x3F & (data[dataIndex + 1] << 2                           ) ];
                    stackBuffer[stackIndex++] = '=';
                }
            }
            sink(stackBuffer[0..stackIndex]);
        }
    }
    return Formatter(data);
}
unittest
{
    import std.format : format;
    assert(format("%s", formatBase64(""))       == "");
    assert(format("%s", formatBase64("f"))      == "Zg==");
    assert(format("%s", formatBase64("fo"))     == "Zm8=");
    assert(format("%s", formatBase64("foo"))    == "Zm9v");
    assert(format("%s", formatBase64("foob"))   == "Zm9vYg==");
    assert(format("%s", formatBase64("fooba"))  == "Zm9vYmE=");
    assert(format("%s", formatBase64("foobar")) == "Zm9vYmFy");
}