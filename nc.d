import std.concurrency;
import std.conv;
import std.getopt;
import std.socket;
import std.stdio;

import core.stdc.stdio;
import core.stdc.stdlib;

import net;

void usage()
{
  writeln("Connect-Mode: nc [-options] <host> <port>");
  writeln("Listen-Mode : nc [-options] <port>");
  writeln("  -l -local-port : ");
}
void main(string[] args)
{
  if(args.length <= 1) {
    usage();
    return;
  }

  ushort localPort = 0;
  string localHost = null;
  uint bufferSize = 2048;

  getopt(args,
	 "l|local-port", &localPort,
         "h|local-host", &localHost,
	 "b|buffer-size", &bufferSize);


  bool listenMode;
  string connectorString;
  string portString;
  if(args.length == 2) {
    listenMode = true;
    if(localPort != 0){
      writeln("You cannot set local port in listen mode");
      return;
    }
    portString = args[1];
  } else if(args.length == 3) {
    listenMode = false;
    if(localHost !is null) {
      writeln("You cannot set the local host in connect mode");
      return;
    }
    connectorString = args[1];
    portString = args[2];
  }

  ushort port;
  try {
    port = to!ushort(portString);
  } catch(ConvException) {
    writefln("'%s' is not a valid port", portString);
    return;
  }

  Socket connectedSocket;
  if(listenMode) {
    writeln("listen mode not implemented");
    return;
  } else {
    ISocketConnector connector;
    string ipOrHost = parseConnector(connectorString, connector);
    Address address = addressFromIPOrHost(ipOrHost, port);

    connectedSocket = new Socket(address.addressFamily(), SocketType.STREAM, ProtocolType.TCP);

    if(localPort != 0) {
      connectedSocket.bind(new InternetAddress(InternetAddress.ADDR_ANY, localPort));
    }

    // Connect
    if(connector is null) connectedSocket.connect(address);
    else connector.connect(connectedSocket, address);
  }

  //
  // Connected Console to TCP Loop
  //
  Tid tid = spawn(&socket2stdout, cast(shared)connectedSocket, bufferSize);

  ubyte[] buffer = (cast(ubyte*)alloca(bufferSize))[0..bufferSize];
  if(buffer == null) throw new Exception("alloca returned null: out of memory");

  //std.stdio.stdin.setvbuf(buffer, _IOLBF);
  std.stdio.stdin.setvbuf(buffer, _IONBF);

  while(true) {
    //writeln("Reading bytes...");std.stdio.stdout.flush();
    size_t bytesRead = fread(buffer.ptr, 1, bufferSize, core.stdc.stdio.stdin);
    //writeln("Read bytes");std.stdio.stdout.flush();
    if(bytesRead <= 0) break;
    connectedSocket.send(buffer[0..bytesRead]);
    //ubyte[] read = std.stdio.stdin.rawRead(buffer);
    //if(read == null || read.length <= 0) break;
    //connectedSocket.send(read);
  }
}



void socket2stdout(shared Socket sharedSocket, uint bufferSize)
{
  ubyte[] buffer = (cast(ubyte*)alloca(bufferSize))[0..bufferSize];
  if(buffer == null) throw new Exception("alloca returned null: out of memory");

  Socket socket = cast(Socket)sharedSocket;

  ptrdiff_t bytesRead;
  while(true) {
    bytesRead = socket.receive(buffer);
    if(bytesRead <= 0) break;
    write(cast(char[])buffer[0..bytesRead]);
    std.stdio.stdout.flush();
  }
}


