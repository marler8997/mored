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
        //getnameinfo, getaddrinfo, freeaddrinfo,
        //closesocket, shutdown, bind, listen, ioctlsocket,
        //connect, send, sendto, recv, recvfrom, socklen_t, accept,
        //sockaddr, sockaddr_in, sockaddr_in6,
        //getsockopt, setsockopt,
        //ntohs, ntohl, htons, htonl,
        //tcp_keepalive,
        FIONBIO;
        //fd_set, FD_SETSIZE, FD_ISSET,
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
    alias _ctimeval = core.sys.windows.winsock2.timeval;
    alias _clinger = core.sys.windows.winsock2.linger;

    import std.windows.syserror : sysErrorString, GetModuleHandleA, GetProcAddress;

    private immutable int _SOCKET_ERROR = core.sys.windows.winsock2.SOCKET_ERROR;

    alias socket_t = size_t;
    alias socklen_t = int;
    //enum socket_t : size_t;
    bool isInvalid(socket_t sock)
    {
        return sock == size_t.max;
    }

    alias sysresult_t = int;
    bool failed(sysresult_t result)
    {
        return result != 0;
    }
    bool success(sysresult_t result)
    {
        return result == 0;
    }

    int lastError()
    {
        return GetLastError();
    }

    private extern(Windows) socket_t socket(int af, SocketType type, Protocol protocol) nothrow @nogc;
    extern(Windows) sysresult_t bind(socket_t sock, sockaddr* addr, uint addrlen);
    extern(Windows) sysresult_t listen(socket_t sock, uint backlog);

    extern(Windows) sysresult_t getsockname(socket_t sock, sockaddr* addr, uint* namelen);

    extern(Windows) sysresult_t ioctlsocket(socket_t sock, uint cmd, void* arg);
    extern(Windows) sysresult_t WSAIoctl(socket_t sock, uint code,
        void* inBuffer, uint inBufferLength,
        void* outBuffer, uint outBufferLength,
        uint* bytesReturned, WSAOVERLAPPED* overlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINE completionRoutine);

    extern(Windows) socket_t WSAAccept(socket_t sock, sockaddr* addr, uint* addrlen, void*, void*);

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
    bool failed(sysresult_t result)
    {
        return result != 0;
    }
    bool success(sysresult_t result)
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
    bool isInvalid(socket_t sock)
    {
        return sock == size_t.max;
    }
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
    extern(C) sysresult_t bind(socket_t sock, sockaddr* addr, uint addrlen);
    extern(C) sysresult_t listen(socket_t sock, uint backlog);
    extern(C) socket_t accept(socket_t sock,  sockaddr* addr, socklen_t* addrlen);
    extern(C) ptrdiff_t recv(socket_t sock, ubyte* buffer, size_t len, uint flags);
    extern(C) ptrdiff_t send(socket_t sock, ubyte* buffer, size_t len, uint flags);
    extern(C) sysresult_t getpeername(socket_t sock, sockaddr* addr, socklen_t* addrlen);
    extern(C) sysresult_t shutdown(socket_t sock, Shutdown how);

}
else
{
    static assert(0, "unhandled platform");
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
        assert(ws2Lib, format("GetModuleHandleA(\"ws2_32.dll\") failed error=%s", WSAGetLastError()));

        /*
        getnameinfoPointer = cast(typeof(getnameinfoPointer))
                             GetProcAddress(ws2Lib, "getnameinfo");
        getaddrinfoPointer = cast(typeof(getaddrinfoPointer))
                             GetProcAddress(ws2Lib, "getaddrinfo");
        if(getaddrinfoPointer)
        {
            freeaddrinfoPointer = cast(typeof(freeaddrinfoPointer))
                                 GetProcAddress(ws2Lib, "freeaddrinfo");
            if(!freeaddrinfoPointer)
            {
                getaddrinfoPointer = null;
            }
        }
        */
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

alias in_port_t = ushort;

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

struct sockaddr
{
    AddressFamily sa_family;
    char[14] sa_data;
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
    this(in_port_t sin_port, in_addr sin_addr)
    {
        ipv4.sin_family = AddressFamily.inet;
        ipv4.sin_port   = sin_port;
        ipv4.sin_addr   = sin_addr;
    }
    this(in_port_t sin6_port, in6_addr sin6_addr)
    {
        ipv4.sin_family = AddressFamily.inet6;
        ipv6.sin6_port   = sin6_port;
        ipv6.sin6_addr   = sin6_addr;
    }
    void toString(scope void delegate(const(char)[]) sink) const
    {
        if(family == AddressFamily.inet) {
          auto addr = ntohl(ipv4.sin_addr.s_addr);
          formattedWrite(sink, "%s.%s.%s.%s:%s",
                         (addr >> 24),
                         (addr >> 16) & 0xFF,
                         (addr >>  8) & 0xFF,
                         (addr >>  0) & 0xFF,
                         ntohs(in_port));
        } else if(family == AddressFamily.inet6) {
          char[INET6_ADDRSTRLEN] str;
          assert(inet_ntop(AddressFamily.inet6, &ipv6.sin6_addr, str.ptr, str.length),
            format("inet_ntop failed (e=%s)", lastError()));
	  formattedWrite(sink, "[%s]:%s", str.ptr[0..core.stdc.string.strlen(str.ptr)],
			 ntohs(in_port));
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
