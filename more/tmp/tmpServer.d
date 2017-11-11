import std.stdio;
import std.getopt;
import std.socket;
import std.bitmanip;
import std.container;
import std.conv;
import std.datetime;
import std.string;
import std.c.string;

import core.stdc.stdlib;
import core.thread;
import core.time;

//import common;
//import frames;
//import net;
import more.net;

immutable ushort DEFAULT_PORT = 2029;

// Tmp Commands
immutable ubyte TO_ACCESSOR_SERVER_INFO         = 0;

immutable ubyte TO_SERVER_OPEN_TUNNEL           = 0;
immutable ubyte TO_SERVER_OPEN_ACCESSSOR_TUNNEL = 1;



//
// Connection Info Bytes
//

// Accessor to TmpServer Flags
immutable ubyte TmpConnectionsRequireTlsFlag    = 0x01;
immutable ubyte TunnelConnectionsRequireTlsFlag = 0x02;


// TmpServer to Accessor Flags
immutable ubyte RequireTlsFlag = 0x01;
immutable ubyte IsTunnelFlag   = 0x02;
bool ReadTlsRequirementFromAccessorToServer(ubyte tls)
{
  if(tls == 0) return false;
  if(tls == 1) return true;
  throw new Exception("Expected response from Accessor to be 0 or 1 but it was not");
}



struct AccessorConnection
{
  Address accessorAddress;
  ISocketConnector connector;
  TlsSettings tlsSettings;

  Socket socket;
  public bool connected;


  public void setConnector(string connectorString)
  {
    string accessorIPOrHostAndOptionalPort = parseConnector(connectorString, connector);

    accessorAddress = addressFromIPOrHostAndOptionalPort(accessorIPOrHostAndOptionalPort, DEFAULT_PORT);
    debug writeln("AccessorConnection.address: ", accessorAddress);
  }

  public bool tryConnect(ubyte[] sendBuffer, ServerInfo serverInfo)
  {
    ubyte connectionInfoPacket[1];

    if(connected) throw new Exception("Called tryConnect on AccessorConnection but it is already connected");

    debug writeln("creating socket to connect to accessor...");
    Socket socket = new Socket(accessorAddress.addressFamily(), SocketType.STREAM, ProtocolType.TCP);

    debug writefln("Connecting to '%s'...", accessorAddress);

    try {
      if(connector is null) {
        debug writeln("No Proxy");
        socket.connect(accessorAddress);
      } else {
        debug writeln("Has Proxy");
        connector.connect(socket, accessorAddress);
      }
    } catch(Exception e) {
      writefln("Failed to connect: %s",  e);
      return false;
    }

    try {
      debug writeln("Connected");
      this.socket = socket;

      //
      // Send initial connection information
      //
      bool setupTls = tlsSettings.requireTlsForTmpConnections;
      connectionInfoPacket[0] = setupTls ? RequireTlsFlag : 0;
      socket.send(connectionInfoPacket);

      //
      // Only receive packet if tls was not required
      //
      if(!tlsSettings.requireTlsForTmpConnections) {
        ptrdiff_t bytesRead = socket.receive(connectionInfoPacket);
        if(bytesRead <= 0) throw new SocketException("Disconnected while waiting for connection info response");
        setupTls = ReadTlsRequirementFromAccessorToServer(connectionInfoPacket[0]);
      }

      //
      //
      //
      SocketSendDataHandler accessorSendHandler;
      accessorSendHandler.socket = socket;

      if(setupTls) {
        throw new Exception("Tls not yet implemented");
      }

      //
      // Send Server Info
      //
      uint serverInfoLength = serverInfo.serialize(sendBuffer.ptr + 4);
      sendBuffer[0] = cast(ubyte)(serverInfoLength >> 24);
      sendBuffer[1] = cast(ubyte)(serverInfoLength >> 16);
      sendBuffer[2] = cast(ubyte)(serverInfoLength >>  8);
      sendBuffer[3] = cast(ubyte)(serverInfoLength      );
      accessorSendHandler.HandleData(sendBuffer[0..serverInfoLength+4]);

      return true;

    } catch(Exception) {
      this.socket = null;
      return false;
    }
  }

}

struct TlsSettings
{
  public bool requireTlsForTmpConnections;
  public this(bool requireTlsForTmpConnections)
  {
    this.requireTlsForTmpConnections = requireTlsForTmpConnections;
  }
}
struct ServerInfo
{
  public string name;
  public ushort heartbeatSeconds;
  public ushort reconnectWaitSeconds;
  /*
  public this()
  {

  }
  */
  public uint serializeLength()
  {
    return
      1 +               // Command ID
      1 + name.length + // Name
      2 +               // heartbeatSeconds
      2 ;               // reconectSeconds
  }
  public uint serialize(ubyte *bytes)
  {
    uint offset = 0;
    bytes[offset] = TO_ACCESSOR_SERVER_INFO;
    offset++;
    bytes[offset] = cast(ubyte)name.length;
    offset++;
    foreach(c ; name) {
      bytes[offset] = c;
      offset++;
    }
    bigEndianSetUshort(bytes + offset, heartbeatSeconds);
    offset += 2;
    bigEndianSetUshort(bytes + offset, reconnectWaitSeconds);
    offset += 2;
    return offset;
  }
  void print()
  {
    writef("{name:\"%s\",heartbeat:%s,reconnect:%s}", name, heartbeatSeconds, reconnectWaitSeconds);
  }
}

void usage()
{
  writeln("tmpServer <Name> <AccessorConnector>");
  writeln(" -h --heartbeat-time    Seconds between sending hearbeats");
  writeln(" -w --reconnect-time    Seconds between trying to reconnect after failed connection");
  writeln(" -r --read-length       Length in bytes of buffer to receive data");
}
void main(string[] args)
{
  ServerInfo serverInfo;
  serverInfo.heartbeatSeconds = 60;
  serverInfo.reconnectWaitSeconds = 60;
  //ushort heartbeatSeconds = 60;
  //ushort reconnectWaitSeconds = 60;
  uint readBufferLength = 4096;

  if(args.length <= 1) {
    usage();
    return;
  }
  getopt(args,
         "h|heartbeat-time", &(serverInfo.heartbeatSeconds),
         "w|reconnect-time", &(serverInfo.reconnectWaitSeconds),
         "r|read-length", &readBufferLength);

  if(args.length != 3) {
    writefln("Error: expected 2 non-option arguments but got %s", args.length - 1);
    usage();
    return;
  }
  serverInfo.name = args[1];
  string accessorConnector = args[2];
  ubyte sendBuffer[256];

  serverInfo.print();
  writeln();

  //
  // Attempt initial connection
  //
  AccessorConnection accessor;
  accessor.setConnector(accessorConnector);
/+
  writeln("Attempting initial connection to accessor...");
  if(accessor.tryConnect(sendBuffer, serverInfo)) {
    writeln("Connected to accessor...need to implement...");
  } else {
    writeln("Connect to accessor failed...need to implement...");
  }
+/

  //
  // Tmp Server Loop
  //

  //ubyte[] buffer = new ubyte[readBufferLength];
  ubyte[] buffer = (cast(ubyte*)alloca(readBufferLength))[0..readBufferLength];
  ArrayList!Socket dataSockets = ArrayList!Socket(16);
  SocketSet selectSockets = new SocketSet();
  ptrdiff_t byteRead;
  int socketsAffected;
  TimeVal timeout;
  Duration reconnectDuration = dur!"seconds"(serverInfo.reconnectWaitSeconds);

  while(true) {
    //
    // Connect to accessor if not connected
    //
    if(!accessor.connected) {
      if(dataSockets.count == 0) {
        while(true) {
          writeln("Attempting to connect to accessor...");
          stdout.flush();
          if(accessor.tryConnect(sendBuffer, serverInfo)) {
            writeln("Connected to accessor...need to implement...");
            stdout.flush();
            break;
          } else {
            writefln("Connect to accessor failed...retry in %s seconds", reconnectDuration.total!"seconds");
            stdout.flush();
            Thread.sleep(reconnectDuration);
          }
        }
      }
    }


    if(accessor.connected) {
      timeout.seconds = serverInfo.heartbeatSeconds;
      selectSockets.add(accessor.socket);
    } else {
      timeout.seconds = serverInfo.reconnectWaitSeconds;
    }
    timeout.microseconds = 0;

    foreach(i; 0..dataSockets.count) {
      selectSockets.add(dataSockets.array[i]);
    }

    socketsAffected = Socket.select(selectSockets, null, null, &timeout);

    if(socketsAffected <= 0) {

    } else {

    }


  }

}
