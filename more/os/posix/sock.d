module more.os.posix.sock;

import more.types : passfail;
import more.c : cint;
import more.os.posix.core :
    FileHandle,
    fcntlGetFlags,
    fcntlSetFlags,
    O_NONBLOCK;

public import more.os.posix.core :
    lastError;

public import core.sys.posix.sys.socket :
    socklen_t,
    AF_UNSPEC,
    AF_UNIX,
    AF_IPX,
    AF_APPLETALK,
    AF_INET,
    AF_INET6,

    SOCK_RAW,
    SOCK_STREAM,
    SOCK_DGRAM,
    SOCK_SEQPACKET,
    SOCK_RDM;
public import core.sys.posix.netinet.in_ :
    IPPROTO_IP,
    IPPROTO_IPV6,
    IPPROTO_ICMP,
    IPPROTO_IGMP,
    IPPROTO_PUP,
    IPPROTO_GGP,
    IPPROTO_IDP,
    IPPROTO_RAW,
    IPPROTO_UDP,
    IPPROTO_TCP;

import more.net.sock :
    AddressFamily, SocketType, Protocol,
    SocketHandle, ntohl, sockaddr, Blocking;

extern (C) nothrow @nogc
{
    const(char)* inet_ntop(int addressFamily, const(void)* addr, char* dst, socklen_t size);
    SocketHandle socket(cint domain, cint type, cint protocol);
}


    version(linux)
    {
        enum : int
        {
            TCP_KEEPIDLE  = 4,
            TCP_KEEPINTVL = 5
        }
    }


/+
/*
static import core.stdc.string;

import std.format : format, formattedWrite;
import std.bitmanip : nativeToBigEndian;
import std.typecons : Flag, Yes, No;
*/
    import core.sys.posix.netdb;
    import core.sys.posix.sys.un : sockaddr_un;
    private import core.sys.posix.fcntl;
    private import core.sys.posix.unistd;
    private import core.sys.posix.arpa.inet;
    private import core.sys.posix.netinet.tcp;
    private import core.sys.posix.netinet.in_;
    private import core.sys.posix.sys.time;
    private import core.sys.posix.sys.select;
    private import core.sys.posix.sys.socket;
    private alias _ctimeval = core.sys.posix.sys.time.timeval;
    private alias _clinger = core.sys.posix.sys.socket.linger;

    private import core.stdc.errno;

    alias socket_t = int;
    enum invalidSocket = -1;
    alias socklen_t = int;

    enum Shutdown
    {
      recv = SHUT_RD,
      send = SHUT_WR,
      both = SHUT_RDWR,
    }

    int lastError() nothrow @nogc
    {
        return errno;
    }

    socket_t createsocket(AddressFamily family, SocketType type, Protocol protocol)
    {
        return socket(family, type, protocol);
    }
    void closesocket(socket_t sock)
    {
      close(sock);
    }
    extern(C) sysresult_t bind(socket_t sock, const(sockaddr)* addr, socklen_t addrlen);
    extern(C) sysresult_t listen(socket_t sock, uint backlog);
    extern(C) socket_t accept(socket_t sock,  const(sockaddr)* addr, socklen_t* addrlen);
    extern(C) ptrdiff_t recv(socket_t sock, ubyte* buffer, size_t len, uint flags);
    extern(C) ptrdiff_t send(socket_t sock, const(ubyte)* buffer, size_t len, uint flags);
    extern(C) sysresult_t getpeername(socket_t sock, sockaddr* addr, socklen_t* addrlen);
    extern(C) sysresult_t shutdown(socket_t sock, Shutdown how);
+/
struct addrinfo
{
    cint      ai_flags;
    cint      ai_family;
    cint      ai_socktype;
    cint      ai_protocol;
    socklen_t ai_addrlen;
    sockaddr* ai_addr;
    char*     ai_canonname;
    addrinfo* ai_next;
}
extern(C) sysresult_t getaddrinfo(const(char)* node, const(char)* service,
    const(addrinfo)* hints, addrinfo** res);
/+
alias in_port_t = ushort;

bool isInvalid(socket_t sock)
{
    return sock == invalidSocket;
}
T ntohs(T)(T value) if(T.sizeof == 2)
{
    auto result = nativeToBigEndian(value);
    return *(cast(T*)&result);
}
T htons(T)(T value) if(T.sizeof == 2)
{
    auto result = nativeToBigEndian(value);
    return *(cast(T*)&result);
}
ushort htons(ushort value)
{
    auto result = nativeToBigEndian(value);
    return *(cast(ushort*)&result);
}
T ntohl(T)(T value) if(T.sizeof == 4)
{
    auto result = nativeToBigEndian(value);
    return *(cast(T*)&result);
}
T htonl(T)(T value) if(T.sizeof == 4)
{
    auto result = nativeToBigEndian(value);
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
struct sockaddr_in
{
    AddressFamily sin_family;
    in_port_t    sin_port;
    in_addr      sin_addr;
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
    in_port_t   sin6_port;
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
        in_port_t in_port;
    }
    sockaddr     sa;
    sockaddr_in  ipv4;
    sockaddr_in6 ipv6;
    this(const in_port_t sin_port, in_addr sin_addr)
    {
        ipv4.sin_family = AddressFamily.inet;
        ipv4.sin_port   = sin_port;
        ipv4.sin_addr   = sin_addr;
    }
    this(const in_port_t sin6_port, in6_addr sin6_addr)
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
sysresult_t bind(T)(socket_t sock, const(T)* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    return bind(sock, cast(sockaddr*)addr, T.sizeof);
}
pragma(inline)
sysresult_t connect(T)(socket_t sock, const(T)* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    return connect(sock, cast(sockaddr*)addr, T.sizeof);
}
pragma(inline)
socket_t accept(T)(socket_t sock, T* addr)
    if( is(T == inet_sockaddr) || is(T == sockaddr_in) /* add more types */ )
{
    socklen_t fromlen = T.sizeof;
    return accept(sock, cast(sockaddr*)addr, &fromlen);
}
pragma(inline)
auto send(T)(socket_t sock, const(T)* buffer, size_t len, uint flags = 0)
    if(T.sizeof == 1 && !is(T == ubyte))
{
    return send(sock, cast(const(ubyte)*)buffer, len, flags);
}
pragma(inline)
auto send(T)(socket_t sock, const(T)[] buffer, uint flags = 0)
    if(T.sizeof == 1)
{
    return send(sock, cast(const(ubyte)*)buffer, buffer.length, flags);
}
pragma(inline)
auto recv(T)(socket_t sock, T* buffer, uint len, uint flags = 0)
    if(T.sizeof == 1 && !is(T == ubyte))
{
    return recv(sock, cast(ubyte*)buffer, len, flags);
}
pragma(inline)
auto recv(T)(socket_t sock, T[] buffer, uint flags = 0)
    if(T.sizeof == 1)
{
    return recv(sock, cast(ubyte*)buffer.ptr, buffer.length, flags);
}
pragma(inline)
auto recvfrom(T,U)(socket_t sock, T[] buffer, uint flags, U* from)
    if(T.sizeof == 1 && is(U == inet_sockaddr) || is(U == sockaddr_in) /* add more types */ )
{
    uint fromlen = U.sizeof;
    return recvfrom(sock, cast(ubyte*)buffer.ptr, buffer.length, flags, cast(sockaddr*)from, &fromlen);
}
pragma(inline)
auto sendto(T,U)(socket_t sock, const(T)[] buffer, uint flags, const(U)* to)
    if(T.sizeof == 1 && is(U == inet_sockaddr) || is(U == sockaddr_in) /* add more types */ )
{
    return sendto(sock, cast(const(ubyte)*)buffer.ptr, buffer.length, flags, cast(const(sockaddr)*)to, U.sizeof);
}
+/