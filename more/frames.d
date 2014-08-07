import std.stdio;
import std.socket;
import std.container;

import std.c.string;

alias void delegate(const ubyte[] data) DataHandler;
struct SocketSendDataHandler
{
  public Socket socket;
  public void HandleData(ubyte[] data)
  {
    socket.send(data);
  }
}

void writeHex(const ubyte[] data) {
  foreach(ubyte b; data) {
    writef(" 0x%02X", b);
  }
}
void writelnHex(const ubyte[] data) {
  data.writeHex();
  writeln();
}


class FrameAndHeartbeatFilter
{
  DataHandler dataHandler;
  void delegate() heartbeatHandler;

  ubyte[] storeBuffer;
  uint storedLength;
  this(DataHandler dataHandler) {
    this(dataHandler, 256);
  }
  this(DataHandler dataHandler, uint initialBufferLength) {
    this.dataHandler = dataHandler;
    storeBuffer = new ubyte[initialBufferLength];
  }
  public void filter(const ubyte[] data) {
    if(data.length <= 0) return;

    //
    // Choose which array to work with
    //
    if(storedLength == 0) {
      handleData(data);
    } else {
      uint combinedLength = storedLength + data.length;
      if(combinedLength > storeBuffer.length) {
	storeBuffer.length = combinedLength;
      }
      memcpy(storeBuffer.ptr + storedLength, data.ptr, data.length);
      handleData(storeBuffer[0..combinedLength]);
    }
  }
  void handleData(const ubyte[] data) {
    debug {
      write("<Enter> handleData([");
      data.writeHex();
      writeln("])");
    }

    uint offset = 0;
    uint dataLeft = data.length;

    //
    // Process the data
    //
    while(true) {
      debug writeln("Start of process data loop");

      //
      // Process the command
      //
      if(dataLeft < 4) {
	//
	// copy left over bytes
	//
	if(offset > 0 || data.ptr != storeBuffer.ptr) {
	  if(storeBuffer.length < 4) storeBuffer.length = 4;
	  debug {
	    write("moving [");
	    data[offset..offset+dataLeft].writeHex();
	    writeln(" ] to store buffer");
	  }
	  memcpy(storeBuffer.ptr, data.ptr + offset, dataLeft);
	}
	storedLength = dataLeft;
	return;
      }

      uint totalFrameLength = 4U + (
			      (cast(uint)data[offset    ] << 24) |
			      (cast(uint)data[offset + 1] << 16) |
			      (cast(uint)data[offset + 2] <<  8) |
			      (cast(uint)data[offset + 3]      ) );

      debug writefln("totalFrameLength %d dataLeft %d", totalFrameLength, dataLeft);
      if(totalFrameLength > dataLeft) {
	//
	// copy left over bytes
	//
	if(offset > 0 || data.ptr != storeBuffer.ptr) {
	  if(storeBuffer.length < totalFrameLength) storeBuffer.length = totalFrameLength;
	  debug {
	    write("moving [");
	    data[offset..offset+dataLeft].writeHex();
	    writeln(" ] to store buffer");
	  }
	  memcpy(storeBuffer.ptr, data.ptr + offset, dataLeft);
	}
	storedLength = dataLeft;
	return;
      }

      debug {
	writef("data offset=%s totalFrameLength=%s:", offset, totalFrameLength);
	data[offset..offset+totalFrameLength].writelnHex();
      }
      dataHandler(data[offset + 4..offset + totalFrameLength]);
      offset += totalFrameLength;
      dataLeft -= totalFrameLength;

      if(dataLeft <= 0) {
	debug writeln("no data left");
	storedLength = 0;
	break;
      }
    }
  }
}
unittest
{
  struct FrameAndHeartbeatTester
  {
    DList!(ubyte[]) nextExpectedFrames;

    public void assertFinished()
    {
      assert(nextExpectedFrames.empty());
    }
    public void expectFrames(ubyte[][] frames...)
    {
      foreach(ubyte[] frame; frames) {
	nextExpectedFrames.insertBack(frame);
      }
    }
    void handleData(const ubyte[] data)
    {
      assert(!nextExpectedFrames.empty());

      if(data.length > 10) {
	writefln("Got Frame [%s bytes...]", data.length);
      } else {
	write("Got Frame [");
	data.writeHex();
	writeln(" ]");
      }

      ubyte[] expectedData = nextExpectedFrames.front();
      nextExpectedFrames.removeFront();


      if(expectedData != data) {
	writeln("Data Mismatch:");
	write("    ExpectedData:");
	expectedData.writelnHex();
	write("    ActualData  :");
	data.writelnHex();
	assert(0);
      }
    }
  }

  FrameAndHeartbeatTester tester;
  FrameAndHeartbeatFilter filter = new FrameAndHeartbeatFilter(&(tester.handleData));

  //
  // Test Heartbeats
  //
  writeln("Test");
  tester.expectFrames([]);
  filter.filter([0,0,0,0]);
  tester.assertFinished();

  writeln("Test");
  tester.expectFrames([],[]);
  filter.filter([0,0,0,0, 0,0,0,0]);
  tester.assertFinished();

  //
  // Test Multiple Calls Bytes Per Frame
  //
  writeln("Test");
  tester.expectFrames([0x1F]);
  filter.filter([0,0,0,1,0x1F]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([0,0,0,1]);
  tester.expectFrames([0x2E]);
  filter.filter([0x2E]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([0,0,0]);
  tester.expectFrames([0x3D]);
  filter.filter([1,0x3D]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([0,0]);
  tester.expectFrames([0x4C]);
  filter.filter([0,1,0x4C]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([0]);
  tester.expectFrames([0x5B]);
  filter.filter([0,0,1,0x5B]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([]);
  tester.expectFrames([0x6A]);
  filter.filter([0,0,0,1,0x6A]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([0,0,0]);
  tester.expectFrames([0x79]);
  filter.filter([1,0x79]);
  tester.assertFinished();


  ubyte lengthBytes[4];
  uint[] frameLengths = [1, 2, 3, 10, 50, 100, 400];
  foreach(frameLength; frameLengths) {
    lengthBytes[0] = cast(ubyte)(frameLength >> 24);
    lengthBytes[1] = cast(ubyte)(frameLength >> 16);
    lengthBytes[2] = cast(ubyte)(frameLength >>  8);
    lengthBytes[3] = cast(ubyte)(frameLength      );

    ubyte[] frame = lengthBytes ~ new ubyte[frameLength];
    for(uint i = 4; i < frame.length; i++) {
      frame[i] = cast(ubyte)(i - 4);
    }

    for(uint filterSize = 1; filterSize <= frameLength + 4; filterSize++) {
      uint offset = 0;
      writefln("Test FilterSize: %s", filterSize);
      while(offset + filterSize < 5) {
	ubyte[] partial = frame[offset..offset+filterSize];

	//write("    filter [");
	//writeHex(partial);
	//writeln("]");

	filter.filter(partial);
	offset += filterSize;
      }
      tester.expectFrames(frame[4..$]);

      //write("    filter [");
      //writeHex(frame[offset..$]);
      //writeln("] (last)");
      filter.filter(frame[offset..$]);
      tester.assertFinished();
    }

  }


  writeln("Test");
  filter.filter([0,0,0]);
  filter.filter([2]);
  filter.filter([0x84]);
  tester.expectFrames([0x84, 0xF0]);
  filter.filter([0xF0]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([0,0]);
  filter.filter([0,2]);
  filter.filter([0x92]);
  tester.expectFrames([0x92, 0xCA]);
  filter.filter([ 0xCA ]);
  tester.assertFinished();

  writeln("Test");
  filter.filter([ 0 ]);
  filter.filter([ 0, 0, 10 ]);
  filter.filter([ 0x12, 0x34, 0x56, 0x78 ]);
  filter.filter([ 0x9A, 0xBC ]);
  tester.expectFrames([ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34 ]);
  filter.filter([ 0xDE, 0xF0, 0x12, 0x34 ]);
  tester.assertFinished();

  //
  // Test Multiple Frames Per Call
  //
  writeln("Test");
  tester.expectFrames([],[ 0xA4 ], [],[ 0x73, 0xF3, 0x29, 0x44 ],[]);
  filter.filter([ 0,0,0,0, 0,0,0,1,0xA4, 0,0,0,0, 0,0,0,4,0x73,0xF3,0x29,0x44, 0,0,0,0 ]);
  tester.assertFinished();

  //
  // Test Overlaping Frames Per Call
  //
  writeln("Test 7");
  tester.expectFrames([],[0xA4]);
  filter.filter([ 0,0,0,0, 0,0,0,1, 0xA4, 0 ]);
  tester.assertFinished();

  tester.expectFrames([ 0x73, 0xF3, 0x29, 0x44 ]);
  filter.filter([0,0,4, 0x73, 0xF3, 0x29, 0x44, 0, 0 ]);
  tester.assertFinished();

  tester.expectFrames([ 0x43, 0xAB, 0x71 ]);
  filter.filter([0,3, 0x43, 0xAB, 0x71, 0,0,0]);
  tester.assertFinished();

  tester.expectFrames([0xF0], [], [0x12, 0x34],[]);
  filter.filter([1,0xF0, 0,0,0,0, 0,0,0,2,0x12,0x34, 0,0,0,0, 0,0,0,2,0xDE]);
  tester.assertFinished();

  tester.expectFrames([0xDE, 0x4B]);
  filter.filter([0x4B]);
  tester.assertFinished();

  writeln("Success");
}

