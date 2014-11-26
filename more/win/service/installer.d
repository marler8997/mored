module more.win.service.installer;

import std.conv : to;
import std.string;

import core.stdc.stdlib : alloca;

import win32.winbase;
import win32.winnt;
import win32.winsvc;

import more.win.common;

pragma(lib, "advapi32.lib");

//
// TODO: convert strings toStringz using the stack
//       possibly create overload that takes windows strings and one that takes d strings and converts
//       them to windows strings on the stack
//


void installService(string serviceName, 
                    string displayName, 
		    string exeName,
                    bool autoStart,
                    string account, 
                    string password)
{
  // Allocate strings on the stack
  TCHAR* stackBuffer = cast(TCHAR*)alloca(TCHAR.sizeof * (
	 serviceName.length + 1 +
	 displayName.length + 1 +
	 exeName.length + 1 +
	 account.length + 1 +
	 password.length + 1 ));

  auto offset = 0;

  auto serviceNamePtr = stackBuffer + offset;
  stackBuffer[offset..offset + serviceName.length] = serviceName;
  offset += serviceName.length;
  stackBuffer[offset++] = '\0';

  auto displayNamePtr = stackBuffer + offset;
  stackBuffer[offset..offset + displayName.length] = displayName;
  offset += displayName.length;
  stackBuffer[offset++] = '\0';

  auto exeNamePtr = stackBuffer + offset;
  stackBuffer[offset..offset + exeName.length] = exeName;
  offset += exeName.length;
  stackBuffer[offset++] = '\0';

  auto accountPtr = stackBuffer + offset;
  stackBuffer[offset..offset + account.length] = account;
  offset += account.length;
  stackBuffer[offset++] = '\0';

  auto passwordPtr = stackBuffer + offset;
  stackBuffer[offset..offset + password.length] = password;
  offset += password.length;
  stackBuffer[offset++] = '\0';

  installService(serviceNamePtr,
		 displayNamePtr,
		 exeNamePtr,
		 autoStart,
		 accountPtr,
		 passwordPtr);
}
void installService(const(TCHAR)* serviceName,
                    const(TCHAR)* displayName,
		    const(TCHAR)* exeName,
                    bool autoStart,
		    const(TCHAR)* account,
                    const(TCHAR)* password)
{
  bool result;

  auto scManager = OpenSCManager(null, null, SC_MANAGER_CONNECT | SC_MANAGER_CREATE_SERVICE);
  if(scManager == null)
    throw new LastErrorException();
  scope(exit) CloseServiceHandle(scManager);

  DWORD serviceStart = autoStart ? SERVICE_AUTO_START : SERVICE_DEMAND_START;
  auto service = CreateService(scManager,
			       serviceName,
			       displayName,
			       SERVICE_QUERY_STATUS,
			       SERVICE_WIN32_OWN_PROCESS,
			       serviceStart,
			       SERVICE_ERROR_NORMAL,
			       exeName,
			       null, 
			       null, 
			       null,
			       account,
			       password);
  if(service == null)
    throw new LastErrorException();
  scope(exit) CloseServiceHandle(service);
}

bool UninstallService(string serviceName)
{
  bool result;
  SC_HANDLE scManager =
    OpenSCManager(null, null, SC_MANAGER_CONNECT);
  if (scManager) {
    SC_HANDLE service = OpenService(scManager,
				    cast (const) cast (char*) toStringz(serviceName),
				    SERVICE_QUERY_STATUS | DELETE);
    if (service) {
      SERVICE_STATUS serviceStatus;
      if (QueryServiceStatus(service, &serviceStatus)) {
	try {
	  if (serviceStatus.dwCurrentState == SERVICE_STOPPED) {
	    result = cast (bool) DeleteService(service);
	  }
	}
	catch (Exception) {
	  result = false;
	}
      }

      CloseServiceHandle(service);
    }
    CloseServiceHandle(scManager);
  }
  return result;
}
