module more.socketserver;

import std.traits : hasMember;
import more.net;

version(Windows)
{
    import core.sys.windows.windows : GetTickCount, timeval, GetLastError;
    alias TimerTime = uint;
    auto getCurrentTimeMillis()
    {
        return GetTickCount();
    }
}

enum EventFlags : ubyte
{
    none  = 0x00,
    read  = 0x01,
    write = 0x02,
    error = 0x04,
    all   = read | write | error,
}

enum NO_TIMER = 0;


enum SelectSet { read = 0, write = 1, error = 2}
struct SelectSetProperties
{
    EventFlags eventFlag;
    string name;
}
__gshared immutable selectSetProps = [
    immutable SelectSetProperties(EventFlags.read, "read"),
    immutable SelectSetProperties(EventFlags.write, "write"),
    immutable SelectSetProperties(EventFlags.error, "error"),
];


struct SocketServer(H)
{
    struct EventSocket
    {
        socket_t handle;
        EventFlags flags;

        void function(EventSocket*) handler;

        // The number of milliseconds until the timer event occurs.
        // 0 means no timer.
        uint timer;
        // The time when the timer expires
        TimerTime timerExpireTime;

        static if( hasMember!(H, "EventSocketMixinTemplate") )
        {
            mixin H.EventSocketMixinTemplate;
        }

        void updateTimerExpireTime()
        {
            if(timer != NO_TIMER)
            {
                timerExpireTime = getCurrentTimeMillis() + timer;
            }
        }
    }

    enum SET_COUNT =
        cast(ubyte)H.ReadEvents +
        cast(ubyte)H.WriteEvents +
        cast(ubyte)H.ErrorEvents;
    static if(H.ReadEvents)
    {
        static if(H.WriteEvents)
        {
            static if(H.ErrorEvents)
                __gshared immutable setIndexToSetPropIndex = [SelectSet.read, SelectSet.write, SelectSet.error];
            else
                __gshared immutable setIndexToSetPropIndex = [SelectSet.read, SelectSet.write];
        }
        else
        {
            static if(H.ErrorEvents)
                __gshared immutable setIndexToSetPropIndex = [SelectSet.read, SelectSet.error];
            else
                __gshared immutable setIndexToSetPropIndex = [SelectSet.read];
        }
    }
    else
    {
        static if(H.WriteEvents)
        {
            static if(H.ErrorEvents)
                __gshared immutable setIndexToSetPropIndex = [SelectSet.write, SelectSet.error];
            else
                __gshared immutable setIndexToSetPropIndex = [SelectSet.write];
        }
        else
        {
            static if(H.ErrorEvents)
                __gshared immutable setIndexToSetPropIndex = [SelectSet.error];
            else
                __gshared immutable setIndexToSetPropIndex = null;
        }
    }

    union select_fd_sets
    {
        struct
        {
            static if(H.ReadEvents)
            {
                fd_set_storage!(H.MaxSocketCount) readSet;
                @property fd_set* readSetPointer() { return readSet.ptr; }
            }
            else
            {
                @property fd_set* readSetPointer() { return null; }
            }

            static if(H.WriteEvents)
            {
                fd_set_storage!(H.MaxSocketCount) writeSet;
                @property fd_set* writeSetPointer() { return writeSet.ptr; }
            }
            else
            {
                @property fd_set* writeSetPointer() { return null; }
            }

            static if(H.ErrorEvents)
            {
                fd_set_storage!(H.MaxSocketCount) errorSet;
                @property fd_set* errorSetPointer() { return errorSet.ptr; }
            }
            else
            {
                @property fd_set* errorSetPointer() { return null; }
            }
        }
        fd_set_storage!(H.MaxSocketCount)[SET_COUNT] sets;
    }

    EventSocket[H.MaxSocketCount] eventSockets;
    size_t reservedSocketCount;

    // Only call inside callbacks, or before calling run
    // TODO: add an option in H to say, canAddFromOtherThread
    //       if this is true then I can implement a locking mechanism
    // The socket gets added on the next loop iteration
    void add(ref const EventSocket socket)
    {
        eventSockets[reservedSocketCount++] = cast(EventSocket)socket;
    }

    static if(H.ImplementStop)
    {
        bool stopOnNextIteration;
        // The socket gets added on the next loop iteration
        void stop()
        {
            stopOnNextIteration = true;
        }
    }

    void run()
    {
        uint activeSocketCount;
        select_fd_sets socketSets;

        for(;;)
        {
            // Add new sockets
            if(reservedSocketCount > activeSocketCount)
            {
                import std.stdio;
                writefln("adding %s sockets (%s total)", reservedSocketCount - activeSocketCount, reservedSocketCount);
                static if(H.TimerEvents)
                {
                    do
                    {
                        eventSockets[activeSocketCount].updateTimerExpireTime();
                        activeSocketCount++;
                    } while(activeSocketCount < reservedSocketCount);
                }
                else
                {
                    activeSocketCount = reservedSocketCount;
                }
            }

            // Remove sockets
            {
                uint removeCount = 0;
                for(uint i = 0; i < activeSocketCount; i++)
                {
                    if( (eventSockets[i].flags & EventFlags.all) == 0 &&
                        eventSockets[i].timer == NO_TIMER)
                    {
                        removeCount++;
                        continue;
                    }
                    if(removeCount)
                    {
                        eventSockets[i-removeCount] = eventSockets[i];
                    }
                }
                if(removeCount)
                {
                    activeSocketCount -= removeCount;
                    reservedSocketCount -= removeCount;
                    import std.stdio;
                    writefln("removed %s sockets (%s sockets left)", removeCount, activeSocketCount);
                }
            }

            if(activeSocketCount == 0)
            {
                break;
            }

            static if(H.ImplementStop)
            {
                if(stopOnNextIteration)
                {
                    import std.stdio; writeln("STOPPING!");
                    for(uint i = 0; i < activeSocketCount; i++)
                    {
                        shutdown(eventSockets[i].handle, Shutdown.both);
                        closesocket(eventSockets[i].handle);
                    }
                    return;
                }
                else
                {
                    import std.stdio; writeln("NOT STOPPING!");
                }
            }
            // TODO: maybe implement a stop feature, this
            //       could be an option for H, something like, H.implementStop

            // Setup the select call
            static if(H.ReadEvents)
                socketSets.readSet.fd_count = 0;
            static if(H.WriteEvents)
                socketSets.writeSet.fd_count = 0;
            static if(H.ErrorEvents)
                socketSets.errorSet.fd_count = 0;

            static if(H.TimerEvents)
            {
                uint soonestTimerEvent = uint.max;
                uint now;
            }

            for(uint i = 0; i < activeSocketCount; i++)
            {
                static if(H.ReadEvents)
                {
                    if(eventSockets[i].flags & EventFlags.read)
                    {
                        socketSets.readSet.addNoCheck(eventSockets[i].handle);
                    }
                }
                static if(H.WriteEvents)
                {
                    if(eventSockets[i].flags & EventFlags.write)
                    {
                        socketSets.writeSet.addNoCheck(eventSockets[i].handle);
                    }
                }
                static if(H.ErrorEvents)
                {
                    if(eventSockets[i].flags & EventFlags.error)
                    {
                        socketSets.errorSet.addNoCheck(eventSockets[i].handle);
                    }
                }
                static if(H.TimerEvents)
                {
                    if(eventSockets[i].timer != NO_TIMER)
                    {
                        if(soonestTimerEvent == uint.max)
                        {
                            now = getCurrentTimeMillis();
                        }

                        auto diff = eventSockets[i].timerExpireTime - now;
                        if(diff >= 0x7FFFFFFF)
                        {
                            diff = 0;
                        }
                        if(diff < soonestTimerEvent)
                        {
                            soonestTimerEvent = diff;
                        }
                    }
                }
            }


            {
                import std.stdio;
                // go in reverse since we probably want to call error callbacks first
                write("select");
                foreach(setIndex; 0..SET_COUNT)
                {
                    writef(" %s(", selectSetProps[setIndexToSetPropIndex[setIndex]].name);
                    bool atFirst = true;
                    foreach(handle; socketSets.sets[setIndex].fd_array[0..socketSets.sets[setIndex].fd_count])
                    {
                        if(atFirst) { atFirst = false; } else { write(", "); }
                        writef("%s", handle);
                    }
                    write(")");
                }
                writeln();
            }

            static if(H.TimerEvents)
            {
                timeval timeout;
                if(soonestTimerEvent != uint.max)
                {
                    if(soonestTimerEvent == 0)
                    {
                        timeout.tv_sec = 0;
                        timeout.tv_usec = 0;
                    }
                    else
                    {
                        timeout.tv_sec  = soonestTimerEvent / 1000;          // seconds
                        timeout.tv_usec = (soonestTimerEvent % 1000) * 1000; // microseconds
                    }
                }
                import std.stdio; writefln("calling select...");
                int selectResult = select(0,
                    socketSets.readSetPointer,
                    socketSets.writeSetPointer,
                    socketSets.errorSetPointer,
                    (soonestTimerEvent == uint.max) ? null : &timeout);
            }
            else
            {
                import std.stdio; writefln("calling select...");
                int selectResult = select(0,
                    socketSets.readSetPointer,
                    socketSets.writeSetPointer,
                    socketSets.errorSetPointer,
                    null);
            }
            import std.stdio; writefln("select returned %d", selectResult);
            if(selectResult < 0)
            {
                import std.conv : to;
                assert(0, "select failed, error: " ~ GetLastError().to!string);
            }

            // Handle read/write/error events
            if(selectResult > 0)
            {
                // go in reverse since we probably want to call error callbacks first
                foreach_reverse(setIndex; 0..SET_COUNT)
                {
                    // The hint keeps track of where the last popped socket was found,
                    // it used to determine where to start searching for the next socket.
                    // If select keeps the sockets in order, then the hint will find the sockets
                    // in the most efficient way possible.
                    uint hint = 0;
                    foreach(handle; socketSets.sets[setIndex].fd_array[0..socketSets.sets[setIndex].fd_count])
                    {
                        uint eventSocketIndex = findSocket(activeSocketCount, eventSockets, handle, &hint);
                        if(eventSocketIndex == activeSocketCount)
                        {
                            import std.conv : to;
                            assert(0, "socket handle " ~ handle.to!string ~ " was in the select set, but not in the eventSockets array");
                            //continue;
                        }

                        // Check if the flag is still set, if not, it could have been removed
                        // by another event callback that was previously called.
                        if(0 == (eventSockets[eventSocketIndex].flags & selectSetProps[setIndexToSetPropIndex[setIndex]].eventFlag))
                        {
                            continue;
                        }


                        eventSockets[eventSocketIndex].handler(&eventSockets[eventSocketIndex]);
                        eventSockets[eventSocketIndex].updateTimerExpireTime();
                    }
                }
            }

            // Handle timer events
            static if(H.TimerEvents)
            {
                if(soonestTimerEvent != uint.max)
                {
                    assert(0, "not implemented");
                }
            }
        }
    }

    // Returns: index on success, count on error
    // hint: contains the guess of where the next socket will be
    uint findSocket(uint count, EventSocket[] eventSockets, socket_t handle, uint* hintReference)
    {
        enum checkHandleCode = q{
            if(handle == eventSockets[i].handle)
            {
                *hintReference = i + 1; // increment for next time
                return i;
            }
        };

        foreach(i; *hintReference..count)
        {
            mixin(checkHandleCode);
        }
        // If we get to this point in the function
        // then the select sockets were out of order so the
        // hint mechanism didn't quite work.  Maybe we could log
        // when this happens to determine whether or not there is
        // a better mechanism to find the sockets.
        foreach(i; 0..*hintReference)
        {
            mixin(checkHandleCode);
        }

        return count; // ERROR
    }
}


unittest
{
    static struct Hooks1
    {
        enum MaxSocketCount = 64;
        enum ReadEvents = true;
        enum WriteEvents = true;
        enum ErrorEvents = true;
        enum TimerEvents = true;
        enum ImplementStop = true;
    }
    static struct Hooks2
    {
        enum MaxSocketCount = 64;
        enum ReadEvents = true;
        enum WriteEvents = true;
        enum ErrorEvents = true;
        enum TimerEvents = false;
        enum ImplementStop = true;
    }
    static struct Hooks3
    {
        enum MaxSocketCount = 64;
        enum ReadEvents = true;
        enum WriteEvents = false;
        enum ErrorEvents = true;
        enum TimerEvents = false;
        enum ImplementStop = true;
    }
    static struct Hooks4
    {
        enum MaxSocketCount = 64;
        enum ReadEvents = true;
        enum WriteEvents = false;
        enum ErrorEvents = true;
        enum TimerEvents = false;
        enum ImplementStop = false;
        mixin template EventSocketMixinTemplate()
        {
            int aCoolNewField;
        }
    }

    {
        auto server = new SocketServer!Hooks1();
    }
    {
        auto server = new SocketServer!Hooks2();
    }
    {
        auto server = new SocketServer!Hooks3();
    }
    {
        auto server = new SocketServer!Hooks4();
    }
}

