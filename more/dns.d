module more.dns;

import std.traits : hasMember;
import std.internal.cstring : tempCString;

version(Windows)
{
    import core.sys.windows.winsock2 :
        AI_NUMERICHOST,
        addrinfo,
        timeval;
}
else version(Posix)
{

}
else
{
    static assert(0, "unhandled platform");
}

import more.net :
    sockaddr,
    inet_sockaddr,
    getaddrinfoPointer, freeaddrinfoPointer,
    AddressFamily,
    AF_UNSPEC, AF_INET, AF_INET6;

template isAddressInfo(T)
{
    enum isAddressInfo =
        hasMember!(T, "addressFamily") &&
        hasMember!(T, "assignTo");
}

struct ipv4ThenIPv6
{
    enum hintsAIFamily = AF_UNSPEC;
    static auto selectAddress(T,U)(T* resolved, U addressList)
    {
        foreach(address; addressList)
        {
            if(address.addressFamily == AF_INET)
            {
                resolved.resolved(address);
                return 0; // success, no errors
            }
        }
        foreach(address; addressList)
        {
            if(address.addressFamily == AF_INET6)
            {
                resolved.resolved(address);
                return 0; // success, no errors
            }
        }
        resolved.noResolution();
        return 0; // success, no errors
    }
}
struct ipv4Only
{
    enum hintsAIFamily = AF_INET;
}
struct ipv6Only
{
    enum hintsAIFamily = AF_INET6;
}

// Returns: error code on failure
auto resolve(Hooks,T)(T* resolved, const(char)[] host)
{
    assert(getaddrinfoPointer, "getaddrinfo function not found");
    assert(host.ptr[host.length] == '\0');

    addrinfo hints;
    hints.ai_flags = AI_NUMERICHOST;
    hints.ai_family = Hooks.hintsAIFamily;

    addrinfo* addressList;
    {
        auto error = getaddrinfoPointer(host.tempCString(), null, null/*&hints*/, &addressList);
        if(error)
        {
            return error;
        }
    }
    scope(exit) freeaddrinfoPointer(addressList);

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

    return Hooks.selectAddress(resolved, AddressRange(AddressInfo(addressList)));
}


void noResolution(inet_sockaddr* addr)
{
    addr.family = AddressFamily.unspecified;
}
void resolved(T)(inet_sockaddr* addr, T addressInfo) if(isAddressInfo!T)
{
    assert(addressInfo.addressFamily == AF_INET ||
           addressInfo.addressFamily == AF_INET6);
    addressInfo.assignTo(&addr.sa);
}