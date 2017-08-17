module more.sha;

import std.format : formattedWrite;
import std.bigint : BigInt;

union Sha1
{
    struct
    {
        uint _0;
        uint _1;
        uint _2;
        uint _3;
        uint _4;
    }
    uint[5] array;
    bool opEquals(const(Sha1) rhs) const
    {
        foreach(i; 0..5)
        {
            if(this.array[i] != rhs.array[i])
            {
                return false;
            }
        }
        return true;
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        formattedWrite(sink, "%08x%08x%08x%08x%08x", _0, _1, _2, _3, _4);
    }
}
Sha1 sha1Hash(T)(const(T)[] data) if(T.sizeof == 1)
{
    auto builder = Sha1Builder();
    builder.put(data);
    return builder.finish();
}

uint circularLeftShift(uint value, uint shift)
{
    return (value << shift) | (value >> (32 - shift));
}

struct Sha1Builder
{
    enum HashByteLength = 20;
    enum BlockByteLength = 64;

    enum InitialHash = Sha1(
        0x67452301,
        0xEFCDAB89,
        0x98BADCFE,
        0x10325476,
        0xC3D2E1F0);

    enum uint K_0 = 0x5A827999;
    enum uint K_1 = 0x6ED9EBA1;
    enum uint K_2 = 0x8F1BBCDC;
    enum uint K_3 = 0xCA62C1D6;

    ubyte[BlockByteLength] unhashedBlock;
    ulong totalBlocksHashed;
    Sha1 currentHash = InitialHash;
    ubyte blockIndex;
    void put(T)(const(T)[] data) if(T.sizeof == 1)
    {
        if(blockIndex + data.length < BlockByteLength)
        {
            unhashedBlock[blockIndex..blockIndex + data.length] = cast(ubyte[])data[];
            blockIndex += data.length;
            return;
        }

        {
            auto copyLength = BlockByteLength - blockIndex;
            unhashedBlock[blockIndex..$] = cast(ubyte[])data[0..copyLength];
            data = data[copyLength..$];
        }
        hashBlock(unhashedBlock);

        for(;data.length >= BlockByteLength;)
        {
            hashBlock(cast(ubyte[])data[0..BlockByteLength]);
            data = data[BlockByteLength..$];
        }

        if(data.length > 0)
        {
            unhashedBlock[0..data.length] = cast(ubyte[])data;
            blockIndex = cast(ubyte)data.length;
        }
    }
    Sha1 finish()
    {
        auto totalBitsHashed = (totalBlocksHashed * 512) + (blockIndex * 8);

        // pad
        unhashedBlock[blockIndex++] = 0x80;
        if(blockIndex > 56)
        {
            unhashedBlock[blockIndex..$] = 0;
            hashBlock(unhashedBlock);
            blockIndex = 0;
        }
        unhashedBlock[blockIndex..56] = 0;
        {
            ubyte index = 0;
            auto shift = 56;
            for(;;)
            {
                unhashedBlock[56 + index] = cast(ubyte)(totalBitsHashed >> shift);
                index++;
                if(index >= 8)
                {
                    break;
                }
                shift -= 8;
            }
        }
        hashBlock(unhashedBlock);
        return currentHash;
    }
    private void hashBlock(ubyte[] block)
    {
        uint[80] W;
        foreach(i; 0..16)
        {
            auto blockIndex = i * 4;
            W[i] = (
                (block[blockIndex + 0] << 24) |
                (block[blockIndex + 1] << 16) |
                (block[blockIndex + 2] <<  8) |
                (block[blockIndex + 3]      ) );
        }
        foreach(i; 16..80)
        {
            W[i] = circularLeftShift(W[i - 3] ^ W[i - 8] ^ W[i - 14] ^ W[i - 16], 1);
        }

        Sha1 tempHash = currentHash;
        foreach(i; 0..20)
        {
            auto temp = circularLeftShift(tempHash._0, 5) + ((tempHash._1 & tempHash._2) | ((~tempHash._1) & tempHash._3)) + tempHash._4 + W[i] + K_0;
            tempHash._4 = tempHash._3;
            tempHash._3 = tempHash._2;
            tempHash._2 = circularLeftShift(tempHash._1, 30);
            tempHash._1 = tempHash._0;
            tempHash._0 = temp;
        }
        foreach(i; 20..40)
        {
            auto temp = circularLeftShift(tempHash._0, 5) + (tempHash._1 ^ tempHash._2 ^ tempHash._3) + tempHash._4 + W[i] + K_1;
            tempHash._4 = tempHash._3;
            tempHash._3 = tempHash._2;
            tempHash._2 = circularLeftShift(tempHash._1, 30);
            tempHash._1 = tempHash._0;
            tempHash._0 = temp;
        }
        foreach(i; 40..60)
        {
            auto temp = circularLeftShift(tempHash._0, 5) + ((tempHash._1 & tempHash._2) | (tempHash._1 & tempHash._3) | (tempHash._2 & tempHash._3)) + tempHash._4 + W[i] + K_2;
            tempHash._4 = tempHash._3;
            tempHash._3 = tempHash._2;
            tempHash._2 = circularLeftShift(tempHash._1, 30);
            tempHash._1 = tempHash._0;
            tempHash._0 = temp;
        }
        foreach(i; 60..80)
        {
            auto temp = circularLeftShift(tempHash._0, 5) + (tempHash._1 ^ tempHash._2 ^ tempHash._3) + tempHash._4 + W[i] + K_3;
            tempHash._4 = tempHash._3;
            tempHash._3 = tempHash._2;
            tempHash._2 = circularLeftShift(tempHash._1, 30);
            tempHash._1 = tempHash._0;
            tempHash._0 = temp;
        }
        foreach(i; 0..5)
        {
            currentHash.array[i] += tempHash.array[i];
        }
        totalBlocksHashed++;
        // TODO: assert if the maximum number of blocks is reached
    }

}

unittest
{
    assert(Sha1(0xda39a3ee, 0x5e6b4b0d, 0x3255bfef, 0x95601890, 0xafd80709) == sha1Hash(null));
    assert(Sha1(0xA9993E36, 0x4706816A, 0xBA3E2571, 0x7850C26C, 0x9Cd0d89D) == sha1Hash("abc"));
    assert(Sha1(0x84983e44, 0x1c3bd26e, 0xbaae4aa1, 0xf95129e5, 0xe54670f1) ==
        sha1Hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"));
}