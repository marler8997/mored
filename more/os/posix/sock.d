module more.os.posix.sock;

import more.types : passfail;
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
    ntohl, sockaddr, Blocking;

/**
SocketHandle is part of the public interface for sock
*/
alias SocketHandle = FileHandle;

extern (C) nothrow @nogc
{
    const(char)* inet_ntop(int addressFamily, const(void)* addr, char* dst, socklen_t size);
}

passfail setMode(SocketHandle sock, Blocking blocking)
{
    auto flags = fcntlGetFlags(sock);
    if (flags.isInvalid)
        return passfail.fail;
    return fcntlSetFlags(sock, flags | O_NONBLOCK);
}
