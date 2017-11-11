
import std.stdio : writeln, writefln;
import std.getopt : getopt;
import std.socket : Socket, Address, SocketType, ProtocolType, InternetAddress, SocketShutdown;
import std.conv : to;

import more.net : ISocketConnector, parseConnector, addressFromIPOrHost;

version(Posix) {
  import std.exception : ErrnoException, errno;

  import std.c.stdlib : malloc;

  import core.sys.posix.netinet.in_;
  import core.sys.posix.arpa.inet;
  import core.sys.posix.sys.socket;
  import core.sys.posix.sys.select;
  import core.sys.posix.unistd;
} else {
  import std.stdio;// : stdin, _IONBF, fread;

  import std.concurrency : spawn, Tid;

  import core.stdc.stdio : stdin;
  import core.stdc.stdlib : alloca;
}

__gshared Socket globalSocket;
__gshared uint bufferSize;

void usage()
{
  writeln("Connect-Mode: nc [-options] <host> <port>");
  writeln("Listen-Mode : nc [-options] -l -p <port>");
  writeln("  -o | --local-host <host>   Bind the local socket to this host/ip");
  writeln("  -p | --port <port>         Bind to the given local port");
  writeln("  -l | --listen              Listen mode");
  writeln("  -b | --buffer-size <size>  Use the given buffer size");
}
int main(string[] args)
{
  try {

    if(args.length <= 1) {
      usage();
      return 0;
    }
    
    string localHostString = null;
    ushort localPort = 0;
    bool listenMode;
    bufferSize = 2048;

    getopt(args,
           "o|local-host", &localHostString,
           "p|port", &localPort,
           "l|listen", &listenMode,
           "b|buffer-size", &bufferSize);

    if(listenMode) {

      if(args.length != 1) {
        writeln("Listen-Mode expects 0 command line arguments but gut %s",
                args.length - 1);
        return 1;
      }

      Address localAddress;
      if(localHostString is null) {
        localAddress = new InternetAddress(InternetAddress.ADDR_ANY, localPort);
      } else {
        throw new Exception("local host string not implemented");
      } 

      auto listenSocket = new Socket(localAddress.addressFamily(),
                                     SocketType.STREAM, ProtocolType.TCP);

      listenSocket.bind(localAddress);
      listenSocket.listen(1);
      
      globalSocket = listenSocket.accept();

    } else {

      if(args.length != 3) {
        writeln("Connect-Mode expects 2 command line arguments but gut %s",
                args.length - 1);
        return 1;
      }

      string connectorString = args[1];
      auto remotePort = to!ushort(args[2]);

      ISocketConnector connector;
      string ipOrHost = parseConnector(connectorString, connector);
      Address address = addressFromIPOrHost(ipOrHost, remotePort);

      globalSocket = new Socket(address.addressFamily(), SocketType.STREAM, ProtocolType.TCP);

      if(localHostString !is null || localPort != 0) {
        writeln("localhost and localport aren't implemented yet");
        //globalSocket.bind(new InternetAddress(InternetAddress.ADDR_ANY, localPort));
        return 1;
      }

      // Connect
      if(connector is null) globalSocket.connect(address);
      else connector.connect(globalSocket, address);

    }

    return netcat();

  } catch(Exception e) {
    writeln(e.msg);
    return 1;
  }
}

version(Posix) {

  int netcat()
  {
    int sock = globalSocket.handle();

    string errnoContext = null;
    {
      fd_set readSockets;
      FD_ZERO(&readSockets);

      debug writefln("[DEBUG] stdin %s socket %s", STDIN_FILENO, sock);

      int maxFD = (sock > STDIN_FILENO) ? sock : STDIN_FILENO;
      maxFD++;

      size_t bufferLength = 2048;
      ubyte* buffer = cast(ubyte*)malloc(bufferLength);

      while(true) {

        FD_SET(STDIN_FILENO, &readSockets);
        FD_SET(sock, &readSockets);

        debug writefln("[DEBUG] select");
        if(select(maxFD, &readSockets, null, null, null) < 0)
          throw new ErrnoException("select failed");

        if(FD_ISSET(STDIN_FILENO, &readSockets)) {

          auto readLength = read(STDIN_FILENO, cast(void*)buffer, bufferLength);
          if(readLength <= 0) {
            errnoContext = "read of stdin failed";
            break;
          }
      
          debug writefln("[DEBUG] stdin read %s bytes", readLength);
          send(sock, cast(void*)buffer, readLength, 0);
      
        }
        if(FD_ISSET(sock, &readSockets)) {
          auto recvLength = recv(sock, cast(void*)buffer, bufferLength, 0);
          debug writefln("[DEBUG] recvLength %s", recvLength);
          if(recvLength <= 0) {
            errnoContext = "recv failed";
            if(recvLength == 0)
              sock = -1;
            break;
          }

          debug writefln("[DEBUG] socket read %s bytes", recvLength);
          write(STDOUT_FILENO, cast(void*)buffer, recvLength);

        }
      }
    }

    auto saveErrno = errno;

    if(sock >= 0) {
      shutdown(sock, SHUT_RDWR);
    }

    if(saveErrno) {
      errno = saveErrno;
      throw new ErrnoException(errnoContext);
    }

    return 0;
  }

} else {

  import core.sync.mutex : Mutex;

  shared bool stopped;
  shared Mutex mutex;

  //
  // Note: the Windows version doesn't quite work yet
  //       it won't close stdin after the socket is closed.
  //       I need to do some research on how to properly
  //       use stdin.

  void stop()
  {
    synchronized( mutex ) {
      if(stopped) return;
      debug {writeln("Stopping..."); stdout.flush(); }
      std.stdio.stdin.close();
      //fclose(core.stdc.stdio.stdin);
      globalSocket.shutdown(SocketShutdown.BOTH);
      globalSocket.close();
      stopped = true;
    }
  }
  int netcat()
  {
    stopped = false;
    mutex = cast(shared Mutex)new Mutex;

    // ubyte[] buffer = (cast(ubyte*)alloca(bufferSize))[0..bufferSize];
    // if(buffer == null) throw new Exception("alloca returned null: out of memory");
    ubyte[] buffer = new ubyte[bufferSize];

    //std.stdio.stdin.setvbuf(buffer, _IOLBF);
    std.stdio.stdin.setvbuf(buffer, _IONBF);

    //
    // Connected Console to TCP Loop
    //
    Tid tid = spawn(&socket2stdout, bufferSize);

    while(true) {
      //writeln("Reading bytes...");std.stdio.stdout.flush();
      size_t bytesRead = fread(buffer.ptr, 1, bufferSize, core.stdc.stdio.stdin);

      if(bytesRead <= 0) {
        debug {writefln("[DEBUG] stdin closed"); stdout.flush(); }
        break;
      }
      debug {writefln("[DEBUG] stdin read %s bytes", bytesRead); stdout.flush(); }
      globalSocket.send(buffer[0..bytesRead]);
    }

    stop();

    return 0;
  }
  void socket2stdout(uint bufferSize)
  {
    ubyte[] buffer = (cast(ubyte*)alloca(bufferSize))[0..bufferSize];
    if(buffer == null) throw new Exception("alloca returned null: out of memory");

    ptrdiff_t bytesRead;
    while(true) {
      bytesRead = globalSocket.receive(buffer);
      if(bytesRead <= 0) {
        debug {writefln("[DEBUG] socket closed by remote host"); stdout.flush(); }
        break;
      }
      debug {writefln("[DEBUG] socket read %s bytes", bytesRead); stdout.flush(); }
      write(cast(char[])buffer[0..bytesRead]);
      std.stdio.stdout.flush();
    }

    stop();
  }
}

