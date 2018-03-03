/**
This module contains windows API definitions that are ABI compatible
but may be slightly enhanced to take advantage of D semantics.
*/
module more.os.windows.sock;

import more.types : passfail;

import more.os.windows.core :
    cint, cuint, WindowsErrorCode, HANDLE,
    GetModuleHandleA, GetProcAddress;
import more.net.sock :
    AddressFamily, SocketType, Protocol,
    ntohl, sockaddr, Blocking;

pragma (lib, "ws2_32.lib");
pragma (lib, "wsock32.lib");

private immutable __gshared typeof(&getnameinfo) getnameinfoPointer;
private immutable __gshared typeof(&getaddrinfo) getaddrinfoPointer;
private immutable __gshared typeof(&freeaddrinfo) freeaddrinfoPointer;

shared static this() @system
{
    {
        WSADATA wsaData;
        auto result = WSAStartup(0x2020, &wsaData);
        import std.format : format;
        assert(result.passed, format("WSAStartup failed (returned %s)", result));
    }

    // Load method extensions

    // These functions may not be present on older Windows versions.
    // See the comment in InternetAddress.toHostNameString() for details.
    auto ws2Lib = GetModuleHandleA("ws2_32.dll");
    //assert(ws2Lib, format("GetModuleHandleA(\"ws2_32.dll\") failed error=%s", WSAGetLastError()));
    if (ws2Lib.isInvalid)
    {
        getnameinfoPointer = cast(typeof(getnameinfoPointer))
                             GetProcAddress(ws2Lib, "getnameinfo");
        getaddrinfoPointer = cast(typeof(getaddrinfoPointer))
                             GetProcAddress(ws2Lib, "getaddrinfo");
        freeaddrinfoPointer = cast(typeof(freeaddrinfoPointer))
                             GetProcAddress(ws2Lib, "freeaddrinfo");
    }
}

shared static ~this() @system nothrow @nogc
{
    version(Windows)
    {
        WSACleanup();
    }
}

enum : cint
{
    SOCKET_ERROR = -1,

    AF_UNSPEC =     0,

    AF_UNIX =       1,
    AF_INET =       2,
    AF_IMPLINK =    3,
    AF_PUP =        4,
    AF_CHAOS =      5,
    AF_NS =         6,
    AF_IPX =        AF_NS,
    AF_ISO =        7,
    AF_OSI =        AF_ISO,
    AF_ECMA =       8,
    AF_DATAKIT =    9,
    AF_CCITT =      10,
    AF_SNA =        11,
    AF_DECnet =     12,
    AF_DLI =        13,
    AF_LAT =        14,
    AF_HYLINK =     15,
    AF_APPLETALK =  16,
    AF_NETBIOS =    17,
    AF_VOICEVIEW =  18,
    AF_FIREFOX =    19,
    AF_UNKNOWN1 =   20,
    AF_BAN =        21,
    AF_ATM =        22,
    AF_INET6 =      23,
    AF_CLUSTER =    24,
    AF_12844 =      25,
    AF_IRDA =       26,
    AF_NETDES =     28,

    AF_MAX =        29,

    PF_UNSPEC     = AF_UNSPEC,

    PF_UNIX =       AF_UNIX,
    PF_INET =       AF_INET,
    PF_IMPLINK =    AF_IMPLINK,
    PF_PUP =        AF_PUP,
    PF_CHAOS =      AF_CHAOS,
    PF_NS =         AF_NS,
    PF_IPX =        AF_IPX,
    PF_ISO =        AF_ISO,
    PF_OSI =        AF_OSI,
    PF_ECMA =       AF_ECMA,
    PF_DATAKIT =    AF_DATAKIT,
    PF_CCITT =      AF_CCITT,
    PF_SNA =        AF_SNA,
    PF_DECnet =     AF_DECnet,
    PF_DLI =        AF_DLI,
    PF_LAT =        AF_LAT,
    PF_HYLINK =     AF_HYLINK,
    PF_APPLETALK =  AF_APPLETALK,
    PF_VOICEVIEW =  AF_VOICEVIEW,
    PF_FIREFOX =    AF_FIREFOX,
    PF_UNKNOWN1 =   AF_UNKNOWN1,
    PF_BAN =        AF_BAN,
    PF_INET6 =      AF_INET6,

    PF_MAX        = AF_MAX,

    SOL_SOCKET = 0xFFFF,

    SO_DEBUG =        0x0001,
    SO_ACCEPTCONN =   0x0002,
    SO_REUSEADDR =    0x0004,
    SO_KEEPALIVE =    0x0008,
    SO_DONTROUTE =    0x0010,
    SO_BROADCAST =    0x0020,
    SO_USELOOPBACK =  0x0040,
    SO_LINGER =       0x0080,
    SO_DONTLINGER =   ~SO_LINGER,
    SO_OOBINLINE =    0x0100,
    SO_SNDBUF =       0x1001,
    SO_RCVBUF =       0x1002,
    SO_SNDLOWAT =     0x1003,
    SO_RCVLOWAT =     0x1004,
    SO_SNDTIMEO =     0x1005,
    SO_RCVTIMEO =     0x1006,
    SO_ERROR =        0x1007,
    SO_TYPE =         0x1008,
    SO_EXCLUSIVEADDRUSE = ~SO_REUSEADDR,

    TCP_NODELAY =    1,

    IP_OPTIONS                  = 1,

    IP_HDRINCL                  = 2,
    IP_TOS                      = 3,
    IP_TTL                      = 4,
    IP_MULTICAST_IF             = 9,
    IP_MULTICAST_TTL            = 10,
    IP_MULTICAST_LOOP           = 11,
    IP_ADD_MEMBERSHIP           = 12,
    IP_DROP_MEMBERSHIP          = 13,
    IP_DONTFRAGMENT             = 14,
    IP_ADD_SOURCE_MEMBERSHIP    = 15,
    IP_DROP_SOURCE_MEMBERSHIP   = 16,
    IP_BLOCK_SOURCE             = 17,
    IP_UNBLOCK_SOURCE           = 18,
    IP_PKTINFO                  = 19,

    IPV6_UNICAST_HOPS =    4,
    IPV6_MULTICAST_IF =    9,
    IPV6_MULTICAST_HOPS =  10,
    IPV6_MULTICAST_LOOP =  11,
    IPV6_ADD_MEMBERSHIP =  12,
    IPV6_DROP_MEMBERSHIP = 13,
    IPV6_JOIN_GROUP =      IPV6_ADD_MEMBERSHIP,
    IPV6_LEAVE_GROUP =     IPV6_DROP_MEMBERSHIP,
    IPV6_V6ONLY = 27,

    SOCK_STREAM =     1,
    SOCK_DGRAM =      2,
    SOCK_RAW =        3,
    SOCK_RDM =        4,
    SOCK_SEQPACKET =  5,

    IPPROTO_IP =    0,
    IPPROTO_ICMP =  1,
    IPPROTO_IGMP =  2,
    IPPROTO_GGP =   3,
    IPPROTO_TCP =   6,
    IPPROTO_PUP =   12,
    IPPROTO_UDP =   17,
    IPPROTO_IDP =   22,
    IPPROTO_IPV6 =  41,
    IPPROTO_ND =    77,
    IPPROTO_RAW =   255,

    IPPROTO_MAX =   256,

    MSG_OOB =        0x1,
    MSG_PEEK =       0x2,
    MSG_DONTROUTE =  0x4,

    SD_RECEIVE =  0,
    SD_SEND =     1,
    SD_BOTH =     2,

    INADDR_ANY =        0,
    INADDR_LOOPBACK =   0x7F000001,
    INADDR_BROADCAST =  0xFFFFFFFF,
    INADDR_NONE =       0xFFFFFFFF,
    ADDR_ANY =          INADDR_ANY,

    AI_PASSIVE = 0x1,
    AI_CANONNAME = 0x2,
    AI_NUMERICHOST = 0x4,
    AI_ADDRCONFIG = 0x0400,
    AI_NON_AUTHORITATIVE = 0x04000,
    AI_SECURE = 0x08000,
    AI_RETURN_PREFERRED_NAMES = 0x010000,

    FIONBIO = cast(int)(IOC_IN | ((uint.sizeof & IOCPARM_MASK) << 16) | (102 << 8) | 126),
}
struct timeval
{
    cint tv_sec;
    cint tv_usec;
}

struct WSADATA
{
    ushort Version;
    ushort HighVersion;
    char[257] Description;
    char[129] SystemStatus;
    ushort MaxSockets;
    ushort MaxUdpDg;
    char* VendorInfo;
}

/**
Represents a socket handle
*/
struct SocketHandle
{
    @property static SocketHandle invalidValue()
    {
        return SocketHandle(size_t.max);
    }

    private size_t value;
    @property bool isInvalid() const
    {
        return value == invalidValue.value;
    }
}

struct SockResult
{
    private cint value;
    // NOTE: we could check that value == SOCKET_ERROR, however, if
    //       a function returned neither 0 or SOCKET_ERROR, then we should
    //       treat it as a failure.
    @property bool failed() const { return value != 0; }
    @property bool passed() const { return value == 0; }
}
struct SockLengthResult
{
    private cint value;
    /**
    NOTE: will return failed if return value is not positive
    */
    @property bool failed() const { return value < 0; }
    @property cuint length() in { assert(!failed); } do
    {
        return cast(cuint)value;
    }
}

struct WSAOVERLAPPED
{
    uint* Internal;
    uint* InternalHigh;
    union
    {
        struct
        {
            uint Offset;
            uint OffsetHigh;
        }
        void* Pointer;
    }
    HANDLE Event;
}

struct WSAOVERLAPPED_COMPLETION_ROUTINE
{
    int placeholder;
}

struct addrinfo
{
    int placeholder;
}

extern(Windows) nothrow @nogc
{
    WindowsErrorCode WSAStartup(ushort VersionRequested, WSADATA* lpWSAData);
    SockResult WSACleanup();

    SocketHandle socket(cint af, cint type, cint protocol) nothrow @nogc;
    SockResult shutdown(SocketHandle sock, Shutdown how);
    SockResult closesocket(SocketHandle);

    SockResult bind(SocketHandle sock, const(sockaddr)* addr, cuint addrlen);
    SockResult connect(SocketHandle sock, const(sockaddr)* addr, cuint addrlen);

    SockResult listen(SocketHandle sock, cuint backlog);

    SocketHandle WSAAccept(SocketHandle sock, sockaddr* addr, uint* addrlen, void*, void*);
    SocketHandle accept(SocketHandle sock, sockaddr* addr, int* addrlen);

    SockResult getsockname(SocketHandle sock, sockaddr* addr, uint* namelen);

    SockResult ioctlsocket(SocketHandle sock, uint cmd, void* arg);
    SockResult WSAIoctl(SocketHandle sock, uint code,
        ubyte* inBuffer, uint inBufferLength,
        ubyte* outBuffer, uint outBufferLength,
        uint* bytesReturned, WSAOVERLAPPED* overlapped, WSAOVERLAPPED_COMPLETION_ROUTINE* completionRoutine);

    SockLengthResult recv(SocketHandle sock, ubyte* buffer, cuint len, cuint flags);
    SockLengthResult send(SocketHandle sock, const(ubyte)* buffer, cuint len, cuint flags);

    SockLengthResult recvfrom(SocketHandle sock, ubyte* buffer,
        uint len, uint flags, sockaddr* from, uint* fromlen);
    SockLengthResult sendto(SocketHandle sock, const(ubyte)* buffer,
        uint len, uint flags, const(sockaddr)* to, uint tolen);

    SockResult gethostname(const(char)* name, cint namelen);
    SockResult getaddrinfo(const(char)* nodename, const(char)* servname,
        const(addrinfo)* hints, addrinfo** res);
    void freeaddrinfo(addrinfo* ai);
    SockResult getnameinfo(const(sockaddr)* sa, SocketHandle salen, char* host,
        cuint hostlen, char* serv, cuint servlen, cuint flags);
}

enum Shutdown
{
  recv = SD_RECEIVE,
  send = SD_SEND,
  both = SD_BOTH,
}
struct fd_set
{
    uint fd_count;
    union
    {
        SocketHandle[0] fd_array_0;
        SocketHandle fd_array_first;
    }
    inout(SocketHandle)* fd_array() inout
    {
        return &fd_array_first;
    }
}
struct fd_set_storage(size_t size)
{
    uint fd_count;
    SocketHandle[size] fd_array;
    @property fd_set* ptr()
    {
        return cast(fd_set*)&this;
    }
    void addNoCheck(SocketHandle sock)
    {
        fd_array[fd_count++] = sock;
    }
}

struct fd_set_dynamic(Allocator)
{
    static size_t fdCountToMemSize(uint fd_count)
    {
        return uint.sizeof + fd_count * SocketHandle.sizeof;
    }
    static uint memSizeToFdCount(size_t memSize)
    {
        if(memSize == 0) return 0;
        return cast(uint)((memSize - uint.sizeof) / SocketHandle.sizeof);
    }

    //static assert(hasMember!(Expander, "expand"), Expander.stringof~" does not have an expand function");
    private fd_set* set;
    private uint fd_capacity;
    @property fd_set* ptr()
    {
        return set;
    }
    void reset()
    {
        if(set)
        {
            set.fd_count = 0;
        }
    }
    void addNoCheck(SocketHandle sock)
    {
        import more.alloc : Mem;

        if(set is null)
        {
            auto mem = Allocator.alloc(Mem(null, 0), fdCountToMemSize(1));
            this.set = cast(fd_set*)mem.ptr;
            this.fd_capacity = memSizeToFdCount(mem.size);
            assert(this.fd_capacity >= 1);
            this.set.fd_count = 1;
            this.set.fd_array_first = sock;
        }
        else
        {
            if(set.fd_count >= fd_capacity)
            {
                auto currentMemSize = fdCountToMemSize(fd_capacity);
                auto mem = Allocator.alloc(Mem(set, currentMemSize), fdCountToMemSize(fd_capacity + 1), 0, currentMemSize);
                this.set = cast(fd_set*)mem.ptr;
                auto newFdCapacity =  memSizeToFdCount(mem.size);
                assert(newFdCapacity > this.fd_capacity);
                this.fd_capacity = newFdCapacity;
            }
            (&set.fd_array_first)[set.fd_count++] = sock;
        }
    }
}
extern(Windows) int select(int ignore, fd_set* readfds, fd_set* writefds, fd_set* exceptfds, timeval* timeout);

SocketHandle createsocket(AddressFamily family, SocketType type, Protocol protocol)
{
    return socket(family, type, protocol);
}

/*
 * Commands for ioctlsocket(),  taken from the BSD file fcntl.h.
 *
 *
 * Ioctl's have the command encoded in the lower word,
 * and the size of any in or out parameters in the upper
 * word.  The high 2 bits of the upper word are used
 * to encode the in/out status of the parameter; for now
 * we restrict parameters to at most 128 bytes.
 */
enum IOCPARM_MASK =  0x7f;            /* parameters must be < 128 bytes */
enum IOC_VOID     =  0x20000000;      /* no parameters */
enum IOC_OUT      =  0x40000000;      /* copy out parameters */
enum IOC_IN       =  0x80000000;      /* copy in parameters */
enum IOC_INOUT    =  IOC_IN | IOC_OUT;
                                        /* 0x20000000 distinguishes new &
                                           old ioctl's */
uint _WSAIO(uint x, uint y)   { return IOC_VOID  | x | y; }
uint _WSAIOR(uint x, uint y)  { return IOC_OUT   | x | y; }
uint _WSAIOW(uint x, uint y)  { return IOC_IN    | x | y; }
uint _WSAIORW(uint x, uint y) { return IOC_INOUT | x | y; }

enum IOC_WS2 = 0x08000000;
enum SIO_GET_EXTENSION_FUNCTION_POINTER = _WSAIORW(IOC_WS2, 6);

/+
LPFN_ACCEPTEX loadAcceptEx(SocketHandle socket)
{
    LPFN_ACCEPTEX functionPointer = null;
    GUID acceptExGuid = WSAID_ACCEPTEX;
    uint bytes;
    if(failed(WSAIoctl(socket, SIO_GET_EXTENSION_FUNCTION_POINTER,
        &acceptExGuid, acceptExGuid.sizeof,
        &functionPointer, functionPointer.sizeof, &bytes, null, null)))
    {
        return null;
    }
    assert(functionPointer, "WSAIoctl SIO_GET_EXTENSION_FUNCTION_POINTER returned success but function pointer is null");
    return functionPointer;
}
+/

passfail setMode(SocketHandle sock, Blocking blocking)
{
    uint ioctlArg = blocking ? 0 : 0xFFFFFFFF;
    return (0 == ioctlsocket(sock, FIONBIO, &ioctlArg)) ? passfail.pass : passfail.fail;
}
