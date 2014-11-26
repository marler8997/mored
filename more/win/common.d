module more.win.common;

import std.stdio : writefln, writeln;
import std.string : format;

import win32.winbase;
import win32.winnt;


static if(TCHAR.sizeof == 1)
{
  string toString(TCHAR[] tstring)
  {
    return cast(string)tstring;
  }
}
else
{
  string toString(TCHAR[] tstring)
  {
    throw new Exception("not implemented");
  }
}

string lastErrorMessage(uint lastError)// @safe nothrow
{
  //auto lastError = GetLastError();
  if(lastError == 0) return "Expected GetLastError() to be non-zero but was 0";

  TCHAR* message;
  auto messageLength =
    FormatMessage(
		  FORMAT_MESSAGE_ALLOCATE_BUFFER |
		  FORMAT_MESSAGE_FROM_SYSTEM |
		  FORMAT_MESSAGE_IGNORE_INSERTS,
		  null,
		  lastError,
		  0U, //MAKELANGID(LANG_NEUTRAL, SUBLAN_DEFAULT),
		  cast(TCHAR*)&message,
		  0, null);

  // remove trailing newlines
  while(messageLength > 0) {
    auto c = message[messageLength - 1];
    if(c != '\n' && c != '\r') break;
    messageLength--;
  }

  if(messageLength == 0) {
    return format("GetLastError() code %s (0x%X)", lastError, lastError);
  }

  return message[0..messageLength].toString();
}

class LastErrorException : Exception
{
  uint lastError;
  this(string file = __FILE__, size_t line = __LINE__) {
    this.lastError = GetLastError();
    super(lastErrorMessage(this.lastError));
  }
}

unittest
{
  for(auto i = 1; i <= 100; i++) {
    SetLastError(i);
    try {
      throw new LastErrorException();
    } catch(LastErrorException e) {
      //writefln("LastError %s: '%s'", e.lastError, e.msg);
    }
  }

}