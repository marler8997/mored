import std.stdio;
import std.socket;

import net;

void main()
{
  Socket socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
  socket.bind(new InternetAddress(InternetAddress.ADDR_ANY, 1234));
  socket.listen(0);

  TempStruct s;

  SimpleSelector selector =
    new SimpleSelector(1024, [ SocketAndHandler(socket, &(s.acceptHandler)) ]);
  selector.start();
}
struct TempStruct
{
  void acceptHandler(ISocketSelector selector, Socket socket)
  {
    Socket newSocket = socket.accept();
    selector.addDataSocket(newSocket, &echoHandler);
  }
  void echoHandler(ISocketSelector selector, Socket socket, ubyte[] data)
  {
    if(data != null && data.length > 0) {
      writeln("Echo: ", data);
      stdout.flush();
      socket.send(data);
    }
  }
}
