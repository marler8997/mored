module more.net.dns;

import std.traits : hasMember;
import std.internal.cstring : tempCString;

import more.c : cint;
import more.sentinel : SentinelArray;
import more.net : SockResult;

version(Windows)
{
    import more.os.windows.sock :
        addrinfo, AI_NUMERICHOST,
        getaddrinfoPointer, freeaddrinfoPointer;
}
else version(Posix)
{
    // TODO: fill this in
}
else
{
    static assert(0, "unhandled platform");
}

import more.net : sockaddr, inet_sockaddr, AddressFamily;

template isAddressInfo(T)
{
    enum isAddressInfo =
        hasMember!(T, "addressFamily") &&
        hasMember!(T, "assignTo");
}

struct StandardAddressSelector
{
    static struct IPv4ThenIPv6
    {
        enum hintsAIFamily = AddressFamily.unspec;
        static SockResult selectAddress(T,U)(T* resolved, U addressList)
        {
            foreach(address; addressList)
            {
                if(address.addressFamily == AddressFamily.inet)
                {
                    resolved.resolved(address);
                    return SockResult.pass;
                }
            }
            foreach(address; addressList)
            {
                if(address.addressFamily == AddressFamily.inet6)
                {
                    resolved.resolved(address);
                    return SockResult.pass;
                }
            }
            resolved.noResolution();
            return SockResult.pass;
        }
    }
    static struct IPv4Only
    {
        enum hintsAIFamily = AddressFamily.inet;
    }
    static struct IPv6Only
    {
        enum hintsAIFamily = AddressFamily.inet6;
    }
}

SockResult getaddrinfo(const(char)* node, const(char)* service,
    const(addrinfo)* hints, addrinfo** result)
{
    version (Windows)
    {
        return getaddrinfoPointer(node, service, hints, result);
    }
    else static assert(0, "OS not supported");
}
void freeaddrinfo(addrinfo* result)
{
    version (Windows)
    {
        freeaddrinfoPointer(result);
    }
    else static assert(0, "OS not supported");
}

// Returns: error code on failure
SockResult resolve(alias AddressSelector = StandardAddressSelector.IPv4ThenIPv6, T)
    (T* resolved, SentinelArray!(const(char)) host)
{
    addrinfo hints;
    hints.ai_flags = AI_NUMERICHOST;
    hints.ai_family = AddressSelector.hintsAIFamily;

    addrinfo* addrList;
    {
        auto result = getaddrinfo(host.ptr, null, &hints, &addrList);
        if(result.failed)
            return result;
    }
    scope(exit) freeaddrinfo(addrList);

    static struct AddressInfo
    {
        addrinfo* ptr;
        alias ptr this;
        @property auto addressFamily() const { return ai_family; }
        void assignTo(sockaddr* dst) const
        {
            (cast(ubyte*)dst)[0..ptr.ai_addrlen] = (cast(ubyte*)ptr.ai_addr)[0..ptr.ai_addrlen];
        }
    }
    static struct AddressRange
    {
        AddressInfo next;
        @property bool empty() { return next.ptr is null; }
        @property auto front() { return next; }
        void popFront()
        {
            next.ptr = next.ptr.ai_next;
        }
    }

    return AddressSelector.selectAddress(resolved, AddressRange(AddressInfo(addrList)));
}

private void noResolution(inet_sockaddr* addr)
{
    addr.family = AddressFamily.unspec;
}
private void resolved(T)(inet_sockaddr* addr, T addressInfo) if(isAddressInfo!T)
{
    assert(addressInfo.addressFamily == AddressFamily.inet ||
           addressInfo.addressFamily == AddressFamily.inet6);
    addressInfo.assignTo(&addr.sa);
}