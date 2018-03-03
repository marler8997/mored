module more.net.sock;

static import core.stdc.string;

import std.format : format, formattedWrite;
import std.bitmanip : nativeToBigEndian;
import std.typecons : Flag, Yes, No;
import bitmanip = std.bitmanip;

version(Windows)
{
    import more.os.windows.sock;
}
else version(Posix)
{
    import more.os.posix.sock;
}
else static assert(0);

enum AddressFamily : ushort
{
    unspecified = AF_UNSPEC,
    unix        = AF_UNIX,
    inet        = AF_INET,
    inet6       = AF_INET6,
    ipx         = AF_IPX,
    appleTalk   = AF_APPLETALK,
}
enum SocketType : int
{
    stream    = SOCK_STREAM,
    dgram     = SOCK_DGRAM,
    raw       = SOCK_RAW,
    rdm       = SOCK_RDM,
    seqPacket = SOCK_SEQPACKET,
}
enum Protocol : int
{
    raw  = IPPROTO_RAW,
    udp  = IPPROTO_UDP,
    tcp  = IPPROTO_TCP,
    ip   = IPPROTO_IP,
    ipv6 = IPPROTO_IPV6,
    icmp = IPPROTO_ICMP,
    igmp = IPPROTO_IGMP,
    ggp  = IPPROTO_GGP,
    pup  = IPPROTO_PUP,
    idp  = IPPROTO_IDP,
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
                assert(inet_ntop(AddressFamily.inet6, &ipv6.sin6_addr, str.ptr, str.length),
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


pragma(inline)
sysresult_t bind(T)(SocketHandle sock, const(T)* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    return bind(sock, cast(sockaddr*)addr, T.sizeof);
}
pragma(inline)
sysresult_t connect(T)(SocketHandle sock, const(T)* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    return connect(sock, cast(sockaddr*)addr, T.sizeof);
}
pragma(inline)
SocketHandle accept(T)(SocketHandle sock, T* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    socklen_t fromlen = T.sizeof;
    return accept(sock, cast(sockaddr*)addr, &fromlen);
}
pragma(inline)
auto send(T)(SocketHandle sock, const(T)* buffer, size_t len, uint flags = 0)
    if(T.sizeof == 1 && !is(T == ubyte))
{
    return send(sock, cast(const(ubyte)*)buffer, len, flags);
}
pragma(inline)
auto send(T)(SocketHandle sock, const(T)[] buffer, uint flags = 0)
    if(T.sizeof == 1)
{
    return send(sock, cast(const(ubyte)*)buffer, buffer.length, flags);
}
pragma(inline)
auto recv(T)(SocketHandle sock, T* buffer, uint len, uint flags = 0)
    if(T.sizeof == 1 && !is(T == ubyte))
{
    return recv(sock, cast(ubyte*)buffer, len, flags);
}
pragma(inline)
auto recv(T)(SocketHandle sock, T[] buffer, uint flags = 0)
    if(T.sizeof == 1)
{
    return recv(sock, cast(ubyte*)buffer.ptr, buffer.length, flags);
}
pragma(inline)
auto recvfrom(T,U)(SocketHandle sock, T[] buffer, uint flags, U* from)
    if(T.sizeof == 1 && is(U == inet_sockaddr) || is(U == sockaddr_in) /* add more types */ )
{
    uint fromlen = U.sizeof;
    return recvfrom(sock, cast(ubyte*)buffer.ptr, buffer.length, flags, cast(sockaddr*)from, &fromlen);
}
pragma(inline)
auto sendto(T,U)(SocketHandle sock, const(T)[] buffer, uint flags, const(U)* to)
    if(T.sizeof == 1 && is(U == inet_sockaddr) || is(U == sockaddr_in) /* add more types */ )
{
    return sendto(sock, cast(const(ubyte)*)buffer.ptr, buffer.length, flags, cast(const(sockaddr)*)to, U.sizeof);
}

alias Blocking = Flag!"blocking";
version(Windows)
{
     public import more.os.windows.sock : setMode;
}
else version(Posix)
{
     public import more.os.posix.sock : setMode;
}
else static assert(0);
