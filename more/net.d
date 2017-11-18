module more.net;

static import core.stdc.string;

import std.format : format, formattedWrite;
import std.bitmanip : nativeToBigEndian;
import std.typecons : Flag, Yes, No;

version(Windows)
{
    pragma (lib, "ws2_32.lib");
    pragma (lib, "wsock32.lib");
    import core.sys.windows.winbase :
        BOOL,
        GUID,
        OVERLAPPED,
        GetLastError;
    import core.sys.windows.mswsock :
        WSAID_ACCEPTEX, LPFN_ACCEPTEX;
    static import core.sys.windows.winsock2;
    import core.sys.windows.winsock2 :
        AF_UNSPEC, AF_UNIX, AF_INET, AF_IPX, AF_APPLETALK, AF_INET6,
        SOCK_STREAM, SOCK_DGRAM, SOCK_RAW, SOCK_RDM, SOCK_SEQPACKET,
        IPPROTO_IP, IPPROTO_ICMP, IPPROTO_IGMP, IPPROTO_GGP, IPPROTO_TCP, IPPROTO_PUP,
        IPPROTO_UDP, IPPROTO_IDP, IPPROTO_RAW, IPPROTO_IPV6,
        WSADATA, WSAStartup, WSACleanup,
        WSAGetLastError,
        WSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE,
        //WSAIoctl,

        // DNS
        AI_NUMERICHOST,
        addrinfo, /*getnameinfo, getaddrinfo, freeaddrinfo,*/

        //closesocket, shutdown, bind, listen, ioctlsocket,
        //connect, send, sendto, recv, recvfrom, socklen_t, accept,
        //sockaddr, sockaddr_in, sockaddr_in6,
        //getsockopt, setsockopt,
        //ntohs, ntohl, htons, htonl,
        //tcp_keepalive,
        FIONBIO,
        //fd_set, FD_SETSIZE, FD_ISSET,
        timeval;
        //SOL_SOCKET,
        //SO_DEBUG, SO_BROADCAST, SO_REUSEADDR, SO_LINGER, SO_OOBINLINE, SO_SNDBUF,
        //SO_RCVBUF, SO_DONTROUTE, SO_SNDTIMEO, SO_RCVTIMEO, SO_ERROR, SO_KEEPALIVE,
        //SO_ACCEPTCONN, SO_RCVLOWAT, SO_SNDLOWAT, SO_TYPE,
        //TCP_NODELAY,
        //IPV6_UNICAST_HOPS, IPV6_MULTICAST_IF, IPV6_MULTICAST_LOOP,
        //IPV6_MULTICAST_HOPS, IPV6_JOIN_GROUP, IPV6_LEAVE_GROUP, IPV6_V6ONLY,
        //AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST,
        //SD_RECEIVE, SD_SEND, SD_BOTH,
        //MSG_OOB, MSG_PEEK, MSG_DONTROUTE,
        //WSAEWOULDBLOCK, WSANO_DATA,
        //NI_NUMERICHOST, NI_MAXHOST, NI_NUMERICSERV, NI_NAMEREQD, NI_MAXSERV,
        //EAI_NONAME;
}
else version(Posix)
{

}
else
{
    static assert(0, "unhandled platform");
}

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

version(Windows)
{
    //alias _ctimeval = core.sys.windows.winsock2.timeval;
    //alias _clinger = core.sys.windows.winsock2.linger;

    import std.windows.syserror : sysErrorString, GetModuleHandleA, GetProcAddress;

    private immutable int _SOCKET_ERROR = core.sys.windows.winsock2.SOCKET_ERROR;

    alias socket_t = size_t;
    enum invalidSocket = size_t.max;
    alias socklen_t = int;
    //enum socket_t : size_t;

    alias sysresult_t = int;
    @property bool failed(sysresult_t result)
    {
        return result != 0;
    }
    @property bool success(sysresult_t result)
    {
        return result == 0;
    }

    int lastError()
    {
        return GetLastError();
    }

    private extern(Windows) socket_t socket(int af, SocketType type, Protocol protocol) nothrow @nogc;

    enum SD_RECEIVE = 0;
    enum SD_SEND    = 1;
    enum SD_BOTH    = 2;
    enum Shutdown
    {
      recv = SD_RECEIVE,
      send = SD_SEND,
      both = SD_BOTH,
    }
    extern(Windows) sysresult_t shutdown(socket_t sock, Shutdown how);
    extern(Windows) int closesocket(socket_t);

    extern(Windows) sysresult_t bind(socket_t sock, const(sockaddr)* addr, uint addrlen);
    extern(Windows) sysresult_t connect(socket_t sock, const(sockaddr)* addr, uint addrlen);

    extern(Windows) sysresult_t listen(socket_t sock, uint backlog);

    extern(Windows) socket_t WSAAccept(socket_t sock, sockaddr* addr, uint* addrlen, void*, void*);
    extern(Windows) socket_t accept(socket_t sock, sockaddr* addr, socklen_t* addrlen);

    extern(Windows) sysresult_t getsockname(socket_t sock, sockaddr* addr, uint* namelen);

    extern(Windows) sysresult_t ioctlsocket(socket_t sock, uint cmd, void* arg);
    extern(Windows) sysresult_t WSAIoctl(socket_t sock, uint code,
        void* inBuffer, uint inBufferLength,
        void* outBuffer, uint outBufferLength,
        uint* bytesReturned, WSAOVERLAPPED* overlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINE completionRoutine);

    extern(Windows) int recv(socket_t sock, ubyte* buffer, uint len, uint flags);
    extern(Windows) int send(socket_t sock, const(ubyte)* buffer, uint len, uint flags);

    extern(Windows) int recvfrom(socket_t sock, ubyte* buffer, uint len, uint flags, sockaddr* from, uint* fromlen);
    extern(Windows) int sendto(socket_t sock, const(ubyte)* buffer, uint len, uint flags, const(sockaddr)* to, uint tolen);

    struct fd_set
    {
        uint fd_count;
        socket_t[0] fd_array;
    }
    struct fd_set_storage(size_t size)
    {
        uint fd_count;
        socket_t[size] fd_array;
        @property fd_set* ptr()
        {
            return cast(fd_set*)&this;
        }
        void addNoCheck(socket_t sock)
        {
            fd_array[fd_count++] = sock;
        }
    }
    extern(Windows) int select(int ignore, fd_set* readfds, fd_set* writefds, fd_set* exceptfds, timeval* timeout);

    socket_t createsocket(AddressFamily family, SocketType type, Protocol protocol)
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

    LPFN_ACCEPTEX loadAcceptEx(socket_t socket)
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


}
else version(Posix)
{
    alias sysresult_t = int;
    @property bool failed(sysresult_t result)
    {
        return result != 0;
    }
    @property bool success(sysresult_t result)
    {
        return result == 0;
    }
    version(linux)
    {
        enum : int
        {
            TCP_KEEPIDLE  = 4,
            TCP_KEEPINTVL = 5
        }
    }

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
    extern(C) sysresult_t bind(socket_t sock, const(sockaddr)* addr, uint addrlen);
    extern(C) sysresult_t listen(socket_t sock, uint backlog);
    extern(C) socket_t accept(socket_t sock,  const(sockaddr)* addr, socklen_t* addrlen);
    extern(C) ptrdiff_t recv(socket_t sock, ubyte* buffer, size_t len, uint flags);
    extern(C) ptrdiff_t send(socket_t sock, const(ubyte)* buffer, size_t len, uint flags);
    extern(C) sysresult_t getpeername(socket_t sock, sockaddr* addr, socklen_t* addrlen);
    extern(C) sysresult_t shutdown(socket_t sock, Shutdown how);

}
else
{
    static assert(0, "unhandled platform");
}

version(Windows)
{
    private immutable typeof(&core.sys.windows.winsock2.getnameinfo) getnameinfoPointer;
    private immutable typeof(&core.sys.windows.winsock2.getaddrinfo) getaddrinfoPointer;
    private immutable typeof(&core.sys.windows.winsock2.freeaddrinfo) freeaddrinfoPointer;
}

shared static this() @system
{
    version(Windows)
    {
        {
            WSADATA wsaData;
            int result = WSAStartup(0x2020, &wsaData);
            assert(result == 0, format("WSAStartup failed (returned %s)", result));
        }

        // Load method extensions


        // These functions may not be present on older Windows versions.
        // See the comment in InternetAddress.toHostNameString() for details.
        auto ws2Lib = GetModuleHandleA("ws2_32.dll");
        //assert(ws2Lib, format("GetModuleHandleA(\"ws2_32.dll\") failed error=%s", WSAGetLastError()));
        if (ws2Lib)
        {
            getnameinfoPointer = cast(typeof(getnameinfoPointer))
                                 GetProcAddress(ws2Lib, "getnameinfo");
            getaddrinfoPointer = cast(typeof(getaddrinfoPointer))
                                 GetProcAddress(ws2Lib, "getaddrinfo");
            freeaddrinfoPointer = cast(typeof(freeaddrinfoPointer))
                                 GetProcAddress(ws2Lib, "freeaddrinfo");
        }
    }
    else version(Posix)
    {
        /*
        getnameinfoPointer = &getnameinfo;
        getaddrinfoPointer = &getaddrinfo;
        freeaddrinfoPointer = &freeaddrinfo;
        */
    }
}

shared static ~this() @system nothrow @nogc
{
    version(Windows)
    {
        WSACleanup();
    }
}

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

alias Blocking = Flag!"blocking";
sysresult_t setMode(socket_t sock, Blocking blocking)
{
    version(Windows)
    {
        uint ioctlArg = blocking ? 0 : 0xFFFFFFFF;
        return ioctlsocket(sock, FIONBIO, &ioctlArg);
    }
    else version(Posix)
    {
        int flags = fcntl(sock, F_GETFL, 0);
        return fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    }
}
