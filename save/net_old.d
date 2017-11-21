module more.net_old;

import std.bitmanip;
import std.conv;
import std.container;
import std.stdio;
import std.socket;
import std.string;

import core.stdc.stdlib;
import core.thread;

import more.common;

/**
   The maximum number of ascii characters of a domain name.
   Note: includes delimiting dots but not a trailing dot.
*/
enum MAX_DOMAIN_NAME_ASCII_CHARS = 253;
/**
   The maximum number of a domain label, which is the string in between
   the dots in a domain name.
 */
enum MAX_DOMAIN_LABEL_ASCII_CHARS = 63;

string tryRemoteAddressString(Socket sock)
{
  Address addr;
  try {
    addr = sock.remoteAddress();
  } catch(Exception e) {
    return "(unknown address)";
  }
  return addr.toString();
}

interface ISocketConnector
{
  void connect(Socket socket, Address address);
  //void connect(Socket socket, InternetAddress address);
}
//alias void delegate(Socket socket, Address address) SocketConnector;


/// examples:
///    http:<ip-or-host>:<port>
///    socks5:<ip-or-host>:<port>
ISocketConnector parseProxy(string proxyString)
{
  if(proxyString == null || proxyString.length <= 0) return null;

  string[] splitStrings = split(proxyString, ":");
  if(splitStrings.length != 3) throw new Exception("Proxy must have at least 2 colons");

  string proxyTypeString = splitStrings[0];
  string ipOrHostString  = splitStrings[1];
  string portString      = splitStrings[2];

  debug writefln("Proxy: '%s' Host: '%s' Port: '%s'", proxyTypeString, ipOrHostString, portString);

  ushort port = to!ushort(portString);

  if(proxyTypeString == "socks4") {
    throw new Exception("Not implemented");
  } else if(proxyTypeString == "socks5") {
    return new Proxy5Connector(addressFromIPOrHost(ipOrHostString, port));
  } else {
    throw new Exception(format("Unknown proxy type '%s'", proxyTypeString));
  }
}
string parseConnector(string connectorString, out ISocketConnector connector)
{
  // Check for proxy
  ptrdiff_t percentIndex = indexOf(connectorString, '%');
  if(percentIndex == -1) {
    connector = null;
    return connectorString;
  } else {
    connector = parseProxy(connectorString[0..percentIndex]);
    return connectorString[percentIndex+1..$];
  }
}

Address addressFromIPOrHostAndPort(const(char)[] ipOrHostAndPort)
{
  ptrdiff_t colonIndex = indexOf(ipOrHostAndPort, ':');

  if(colonIndex == -1)
    throw new Exception(format("ipOrHost '%s' is missing a colon to indicate the port", ipOrHostAndPort));

  auto ipOrHost = ipOrHostAndPort[0..colonIndex];
  auto port = to!ushort(ipOrHostAndPort[colonIndex+1..$]);

  return addressFromIPOrHost(ipOrHost, port);
}

Address addressFromIPOrHostAndOptionalPort(string ipOrHostAndOptionalPort, ushort defaultPort)
{
  ptrdiff_t colonIndex = indexOf(ipOrHostAndOptionalPort, ':');

  string ipOrHost;
  ushort port;

  if(colonIndex == -1) {
    ipOrHost = ipOrHostAndOptionalPort;
    port = defaultPort;
  } else {
    ipOrHost = ipOrHostAndOptionalPort[0..colonIndex];
    port = to!ushort(ipOrHostAndOptionalPort[colonIndex+1..$]);
  }

  return addressFromIPOrHost(ipOrHost, port);
}
auto addressFromIPOrHost(const(char)[] ipOrHost, ushort port)
{
/+
  debug writefln("Parsing Address '%s' (port=%s)", ipOrHost, port);
  Address addr = parseAddress(ipOrHost, port);
  debug writeln("done");
  return addr;
+/
  //return parseAddress(ipOrHost, port);
  return new InternetAddress(ipOrHost, port);
}


void receiveAll(Socket socket, ubyte[] buffer)
{
  ptrdiff_t lastBytesRead;
  do {
    lastBytesRead = socket.receive(buffer);
    buffer = buffer[lastBytesRead..$];
    if(buffer.length <= 0) return;
  } while(lastBytesRead > 0);
  throw new Exception("socket closed but still expected more data");
}



class Proxy5Connector : ISocketConnector
{
  Address proxyAddress;
  this(Address proxyAddress) {
    this.proxyAddress = proxyAddress;
  }
  public void connect(Socket socket, Address address)
  {
    InternetAddress inetAddress = cast(InternetAddress)address;

    if(!(inetAddress is null)) {
      proxy5connect(socket, proxyAddress, inetAddress);
      return;
    }

    throw new Exception(format("The Proxy5 connector does not handle addresses of type '%s'", typeid(address)));
  }
}


void proxy5connect(Socket socket, Address proxy, InternetAddress address)
{
  debug writefln("Proxy5: Final Destination: '%s'", address);

  ubyte buffer[21];

  debug writefln("Connecting to Proxy '%s'", proxy);
  socket.connect(proxy);
  debug writeln("Connected");

  //
  // Send initial greeting
  //
  buffer[0] = 5; // SOCKS version 5
  buffer[1] = 1; // 1 Authentication protocol
  buffer[2] = 0; // No authentication
  debug writeln("Proxy5: Sending initial greeting...");
  socket.send(buffer[0..3]);

  //
  // Get response
  //
  debug writeln("Proxy5: Receiving response...");
  socket.receiveAll(buffer[0..2]);
  if(buffer[0] != 5) throw new Exception("The given proxy does not support SOCKS version 5");
  if(buffer[1] != 0) throw new Exception("Server does not support NO_AUTHENTICATION");

  //
  // Send CONNECT command
  //
  buffer[0] = 5; // SOCKS version 5
  buffer[1] = 1; // CONNECT command
  buffer[2] = 0; // Reserved

  uint ip = address.addr();
  debug writeln("Converting address to big endian...");
  ubyte[4] ipNetworkOrder = nativeToBigEndian(ip);
  debug writeln("Done");
  buffer[3] = 1; // IPv4 address
  buffer[4] = ipNetworkOrder[0];
  buffer[5] = ipNetworkOrder[1];
  buffer[6] = ipNetworkOrder[2];
  buffer[7] = ipNetworkOrder[3];

  ushort port = address.port();
  buffer[8] = cast(ubyte)(port >> 8);
  buffer[9] = cast(ubyte)(port     );
  debug writeln("Proxy5: Sending CONNECT");
  socket.send(buffer[0..10]);

  //
  // Get final response
  //
  socket.receiveAll(buffer[0..10]);
  if(buffer[1] != 0) throw new Exception("Proxy server failed to connect to host");
}





class TunnelThread : Thread
{
  public Socket socketA, socketB;
  this()
  {
    super( &run );
  }
  void run() {
    SocketSet selectSockets;
    ubyte[] buffer = new ubyte[1024];

    while(true) {
      selectSockets.add(socketA);
      selectSockets.add(socketB);

      Socket.select(selectSockets, null, null);

      ptrdiff_t bytesRead;
      if(selectSockets.isSet(socketA)) {
        bytesRead = socketA.receive(buffer);
        if(bytesRead == 0) {
          socketB.shutdown(SocketShutdown.BOTH);
          break;
        }
        socketB.send(buffer);
      }
      if(selectSockets.isSet(socketB)) {
        bytesRead = socketB.receive(buffer);
        if(bytesRead == 0) {
          socketA.shutdown(SocketShutdown.BOTH);
          break;
        }
        socketA.send(buffer);
      }
    }
    socketA.close();
    socketB.close();
  }
}

struct Tunnels
{
  public static void add(Socket socketA, Socket socketB)
  {
    TunnelThread tunnel;
    tunnel.socketA = socketA;
    tunnel.socketB = socketB;
    tunnel.start();
  }
}


struct TcpSocketPair {
  Socket socketA, socketB;
}

alias void delegate(ISocketSelector selector, Socket socket) SocketHandler;

// Called with null if the socket was closed
alias void delegate(ISocketSelector selector, ref DataSocketAndHandler handler, ubyte[] data) DataSocketHandler;


interface ISocketSelector
{
  void addSocket(Socket socket, SocketHandler handler);
  void addDataSocket(Socket socket, DataSocketHandler handler);
}

struct SocketAndHandler
{
  public Socket socket;
  public SocketHandler handler;
}

struct DataSocketAndHandler
{
  public Socket socket;
  public DataSocketHandler handler;
}

/// You cannot manually remove data sockets, they must be shutdown to be removed.
/// This is so the select loops will not be messed up.
class SimpleSelector : Thread, ISocketSelector
{
  const size_t bufferSize;
  ArrayList!SocketAndHandler handlers;
  ArrayList!DataSocketAndHandler dataHandlers;
  public this(T)(size_t bufferSize, T initialHandlers)
  {
    super(&run);
    this.bufferSize = bufferSize;
    this.handlers = ArrayList!SocketAndHandler(initialHandlers);
    this.dataHandlers = ArrayList!(DataSocketAndHandler)(16);
  }

  /// Note: this method must add the socket to the end of the socket list
  ///       in order to not mess up the select loop
  void addSocket(Socket socket, SocketHandler handler)
  {
    SocketAndHandler s = SocketAndHandler(socket, handler);
    handlers.put(s);
  }
  /// Note: this method must add the socket to the end of the socket list
  ///       in order to not mess up the select loop
  void addDataSocket(Socket socket, DataSocketHandler handler)
  {
    DataSocketAndHandler s = DataSocketAndHandler(socket, handler);
    dataHandlers.put(s);
    debug{writefln("Added DataSocket '%s' (%s total data sockets)", socket.tryRemoteAddressString(), dataHandlers.count); stdout.flush();}
  }
  void run()
  {
    ubyte[] buffer = new ubyte[bufferSize];
    //ubyte[] buffer = (cast(ubyte*)alloca(bufferSize))[0..bufferSize];

    SocketSet selectSockets = new SocketSet();
    ptrdiff_t bytesRead;
    int socketsAffected;

  SELECT_LOOP_START:
    while(true) {
      selectSockets.reset();
      foreach(i; 0..handlers.count) {
        selectSockets.add(handlers.array[i].socket);
      }
      foreach(i; 0..dataHandlers.count) {
        selectSockets.add(dataHandlers.array[i].socket);
      }

      socketsAffected = Socket.select(selectSockets, null, null);

      if(socketsAffected <= 0) throw new Exception(format("Select returned %s but no timeout was specified", socketsAffected));

      // Handle regular sockets
      foreach(i; 0..handlers.count) {
        SocketAndHandler handler = handlers.array[i];
        if(selectSockets.isSet(handler.socket)) {
          handler.handler(this, handler.socket);
          socketsAffected--;
          if(socketsAffected == 0) goto SELECT_LOOP_START;
        }
      }
      // Handle data sockets
      for(size_t i = 0; i < dataHandlers.count; i++) {
        auto socket = dataHandlers.array[i].socket;
        if(selectSockets.isSet(socket)) {
          bytesRead = socket.receive(buffer);
          if(bytesRead <= 0) {
            dataHandlers.array[i].handler(this, dataHandlers.array[i], null);
            dataHandlers.removeAt(i);
            i--;
            debug{writefln("Removed DataSocket '%s' (%s data sockets left)", socket.tryRemoteAddressString(), dataHandlers.count);stdout.flush();}
          } else {
            debug{writefln("Received %s bytes", bytesRead);stdout.flush();}
            dataHandlers.array[i].handler(this, dataHandlers.array[i], buffer[0..bytesRead]);
            if(dataHandlers.array[i].handler is null) {
              try { socket.shutdown(SocketShutdown.BOTH); } catch { }
              try { socket.close(); } catch { }
              dataHandlers.removeAt(i);
              i--;
            }
          }
          socketsAffected--;
          if(socketsAffected == 0) goto SELECT_LOOP_START;
        }
      }
    }
  }
}
