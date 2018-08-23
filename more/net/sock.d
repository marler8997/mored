/**
Contains a platform independent socket library.

Use SocketHandle to represent a handle to a socket.

This file should contain the public platform independent interface to the socket library.
If you want platform dependent definitions, you can import more.net.os.<platform>.sock.

Anything that can be exposed as platform-independent should be defined in this module.
*/
module more.net.sock;

static import core.stdc.string;

import std.format : format, formattedWrite;
import std.bitmanip : nativeToBigEndian;
import std.typecons : Flag, Yes, No;
import bitmanip = std.bitmanip;

import more.types : passfail;
import more.c : cint, cuint;
import more.format : StringSink;
version(Windows)
{
    import platform_sock = more.os.windows.sock;
    public import more.os.windows.core : lastError;
}
else version(Posix)
{
    import platform_sock = more.os.posix.sock;
    import platform_core = more.os.posix.core;
    public import more.os.posix.core : lastError;
}
else static assert(0);

enum AddressFamily : ushort
{
    unspec    = platform_sock.AF_UNSPEC,
    unix      = platform_sock.AF_UNIX,
    inet      = platform_sock.AF_INET,
    inet6     = platform_sock.AF_INET6,
    ipx       = platform_sock.AF_IPX,
    appleTalk = platform_sock.AF_APPLETALK,
}
enum SocketType : int
{
    stream    = platform_sock.SOCK_STREAM,
    dgram     = platform_sock.SOCK_DGRAM,
    raw       = platform_sock.SOCK_RAW,
    rdm       = platform_sock.SOCK_RDM,
    seqPacket = platform_sock.SOCK_SEQPACKET,
}
enum Protocol : int
{
    raw  = platform_sock.IPPROTO_RAW,
    udp  = platform_sock.IPPROTO_UDP,
    tcp  = platform_sock.IPPROTO_TCP,
    ip   = platform_sock.IPPROTO_IP,
    ipv6 = platform_sock.IPPROTO_IPV6,
    icmp = platform_sock.IPPROTO_ICMP,
    igmp = platform_sock.IPPROTO_IGMP,
    ggp  = platform_sock.IPPROTO_GGP,
    pup  = platform_sock.IPPROTO_PUP,
    idp  = platform_sock.IPPROTO_IDP,
}

T ntohs(T)(T value) if(T.sizeof == 2)
{
    auto result = bitmanip.nativeToBigEndian(value.toUshort);
    return *(cast(T*)&result);
}
T htons(T)(T value) if(T.sizeof == 2)
{
    auto result = bitmanip.nativeToBigEndian(value.toUshort);
    return *(cast(T*)&result);
}
ushort htons(ushort value)
{
    auto result = bitmanip.nativeToBigEndian(value);
    return *(cast(ushort*)&result);
}
T ntohl(T)(T value) if(T.sizeof == 4)
{
    auto result = bitmanip.nativeToBigEndian(value);
    return *(cast(T*)&result);
}
T htonl(T)(T value) if(T.sizeof == 4)
{
    auto result = bitmanip.nativeToBigEndian(value);
    return *(cast(T*)&result);
}


struct in_addr
{
    @property static in_addr any() { return in_addr(0); }
    uint s_addr;
}
struct in6_addr
{
    @property static in6_addr any() { return in6_addr(); }
    ubyte[16] s6_addr;
}

union inet_addr
{
    in_addr ipv4;
    in6_addr ipv6;
}

struct sockaddr
{
    AddressFamily sa_family;
    char[14] sa_data;
    /*
    static void assign(sockaddr* dst, sockaddr* src)
    {
        auto size = sockaddrsize(src.sa_family);
        (cast(ubyte*)dst)[0..size] == (cast(ubyte*)src)[0..size];
    }
    */
}

struct Port
{
    private ushort value;
    ushort toUshort() const { return value; }
    void toString(StringSink sink) const
    {
        formattedWrite(sink, "%s", toUshort);
    }
}
pragma(inline) ushort toUshort(ushort value) { return value; }

struct sockaddr_in
{
    AddressFamily sin_family;
    Port sin_port;
    in_addr sin_addr;
    version(Windows)
    {
        char[] sin_zero;
    }
    bool equals(ref const(sockaddr_in) other) const
    {
        return sin_port == other.sin_port &&
            sin_addr.s_addr == other.sin_addr.s_addr;
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        assert(sin_family == AddressFamily.inet);
        auto addr = ntohl(sin_addr.s_addr);
        formattedWrite(sink, "%s.%s.%s.%s:%s",
                      (addr >> 24),
                      (addr >> 16) & 0xFF,
                      (addr >>  8) & 0xFF,
                      (addr >>  0) & 0xFF,
                      ntohs(sin_port));
    }
}
struct sockaddr_in6
{
    AddressFamily sin6_family;
    Port   sin6_port;
    uint        sin6_flowinfo;
    in6_addr    sin6_addr;
    uint        sin6_scope_id;
}


private enum INET6_ADDRSTRLEN = 46;

// a sockaddr meant to hold either an ipv4 or ipv6 socket address.
union inet_sockaddr
{
    struct
    {
        AddressFamily family;
        Port in_port;
    }
    sockaddr     sa;
    sockaddr_in  ipv4;
    sockaddr_in6 ipv6;
    this(const Port sin_port, in_addr sin_addr)
    {
        ipv4.sin_family = AddressFamily.inet;
        ipv4.sin_port   = sin_port;
        ipv4.sin_addr   = sin_addr;
    }
    this(const Port sin6_port, in6_addr sin6_addr)
    {
        ipv4.sin_family = AddressFamily.inet6;
        ipv6.sin6_port   = sin6_port;
        ipv6.sin6_addr   = sin6_addr;
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        if(family == AddressFamily.inet)
        {
            ipv4.toString(sink);
        }
        else if(family == AddressFamily.inet6)
        {
            char[INET6_ADDRSTRLEN] str;
            version(Windows)
            {
                assert(0, "inet_sockaddr ipv6 toString not implemented");
            }
            else
            {
                assert(platform_sock.inet_ntop(AddressFamily.inet6, &ipv6.sin6_addr, str.ptr, str.length),
                    format("inet_ntop failed (e=%s)", lastError()));
            }
            formattedWrite(sink, "[%s]:%s", str.ptr[0..core.stdc.string.strlen(str.ptr)], ntohs(in_port));
        } else {
          formattedWrite(sink, "<unknown_family:%s>", family);
        }
    }
    bool equals(ref const(inet_sockaddr) other) const
    {
        if(family != other.family || in_port != other.in_port)
            return false;
        if(family == AddressFamily.inet) {
            return ipv4.sin_addr.s_addr == other.ipv4.sin_addr.s_addr;
        } else if(family == AddressFamily.inet6) {
            assert(0, "not implemented");
        } else {
            assert(0, "not currently handled");
        }
    }
}

version (Windows)
{
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
}
else version(Posix)
{
    alias SocketHandle = platform_core.FileHandle;
}

struct SockResult
{
    static SockResult pass() { return SockResult(0); }

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
struct SendResult
{
    private SockLengthResult result;
    private cuint expected;
    @property bool failed() const { return result.failed; }
    /**
    NOTE: will return failed if return value is not positive
    */
    @property bool sentAll() const { return result.value == expected; }
    @property auto sent() const { return result.value; }
}

SocketHandle createsocket(AddressFamily family, SocketType type, Protocol protocol)
{
    return platform_sock.socket(family, type, protocol);
}

version (Windows)
{
    extern(Windows) nothrow @nogc
    {
        SockResult closesocket(SocketHandle);
    }
}
else version (Posix)
{
    pragma(inline) int closesocket(SocketHandle handle) nothrow @nogc
    {
        return platform_core.close(handle);
    }
}
else
{
    static assert(0, "closesocket not declared for this OS");
}

pragma(inline)
auto bind(T)(SocketHandle sock, const(T)* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    return platform_sock.bind(sock, cast(const(sockaddr)*)addr, T.sizeof);
}
pragma(inline)
auto connect(T)(SocketHandle sock, const(T)* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    return platform_sock.connect(sock, cast(sockaddr*)addr, T.sizeof);
}
pragma(inline)
auto accept(T)(SocketHandle sock, T* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    socklen_t fromlen = T.sizeof;
    return platform_sock.accept(sock, cast(sockaddr*)addr, &fromlen);
}
pragma(inline)
auto send(T)(SocketHandle sock, const(T)* buffer, size_t len, uint flags = 0)
    if(T.sizeof == 1 && !is(T == ubyte))
{
    return platform_sock.send(sock, cast(const(ubyte)*)buffer, len, flags);
}
pragma(inline)
auto send(T)(SocketHandle sock, const(T)[] buffer, uint flags = 0)
    if(T.sizeof == 1)
{
    return platform_sock.send(sock, cast(const(ubyte)*)buffer, buffer.length, flags);
}
pragma(inline)
auto recv(T)(SocketHandle sock, T* buffer, uint len, uint flags = 0)
    if(T.sizeof == 1 && !is(T == ubyte))
{
    return platform_sock.recv(sock, cast(ubyte*)buffer, len, flags);
}
pragma(inline)
auto recv(T)(SocketHandle sock, T[] buffer, uint flags = 0)
    if(T.sizeof == 1)
{
    return platform_sock.recv(sock, cast(ubyte*)buffer.ptr, buffer.length, flags);
}
pragma(inline)
auto recvfrom(T,U)(SocketHandle sock, T[] buffer, uint flags, U* from)
    if(T.sizeof == 1 && is(U == inet_sockaddr) || is(U == sockaddr_in) /* add more types */ )
{
    uint fromlen = U.sizeof;
    return platform_sock.recvfrom(sock, cast(ubyte*)buffer.ptr, buffer.length, flags, cast(sockaddr*)from, &fromlen);
}
pragma(inline)
auto sendto(T,U)(SocketHandle sock, const(T)[] buffer, uint flags, const(U)* to)
    if(T.sizeof == 1 && is(U == inet_sockaddr) || is(U == sockaddr_in) /* add more types */ )
{
    auto sent = platform_sock.sendto(sock, cast(const(ubyte)*)buffer.ptr, buffer.length, flags, cast(const(sockaddr)*)to, U.sizeof);
    return SendResult(sent, buffer.length);
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
version (Windows)
{
    extern(Windows) nothrow @nogc
    {
        // TODO: return value should by typed
        int select(int ignore, fd_set* readfds, fd_set* writefds, fd_set* exceptfds, platform_sock.timeval* timeout);
    }
}



alias Blocking = Flag!"blocking";

passfail setMode(SocketHandle sock, Blocking blocking)
{
    version (Windows)
    {
        uint ioctlArg = blocking ? 0 : 0xFFFFFFFF;
        return platform_sock.ioctlsocket(sock, platform_sock.FIONBIO, &ioctlArg).passed ? passfail.pass : passfail.fail;
    }
    else
    {
        auto flags = platform_core.fcntlGetFlags(sock);
        if (flags.isInvalid)
            return passfail.fail;
        return platform_core.fcntlSetFlags(sock, flags | platform_core.O_NONBLOCK);
    }
}
