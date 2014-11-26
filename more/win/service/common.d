module more.win.service;

import core.thread;
import std.conv : to;
import std.string;
import win32.winbase;
import win32.winnt;
import win32.winsvc;

abstract class ServiceBase
{
  private shared static ServiceBase singleton;
  private static ServiceBase _service;

  private shared {
    string _serviceName;
    string _displayName;
    DWORD _controlsAccepted = 0;
  }

  private  {
    SERVICE_STATUS _serviceStatus;
    SERVICE_STATUS_HANDLE _serviceStatusHandle;
    DWORD _checkPoint = 1;
  }

  // Register the executable for a service with the Service Control Manager 
  // (SCM). After you call Run(ServiceBase), the SCM issues a Start command, 
  // which results in a call to the OnStart method in the service. This 
  // method blocks until the service has stopped.
  public static void Run(ServiceBase service)
  {
    singleton = cast (shared(ServiceBase)) service;
    SERVICE_TABLE_ENTRY[] serviceTable =
      [
       SERVICE_TABLE_ENTRY(cast (char*) toStringz(singleton._serviceName), &singleton.ServiceMain),
       SERVICE_TABLE_ENTRY(null, null)
       ];
    StartServiceCtrlDispatcher(serviceTable.ptr);
  }

public:
  // Service object constructor. The optional parameters (canStop, 
  // canShutdown and canPauseContinue) allow you to specify whether the 
  // service can be stopped, paused and continued, or be notified when 
  // system shutdown occurs.
  this(string serviceName,
       string displayName,
       bool canStop = true, 
       bool canShutdown = true, 
       bool canPauseContinue = false)
  {
    _serviceName = serviceName;
    _displayName = displayName;

    // The accepted commands of the service.
    if (canStop) 
      _controlsAccepted |= SERVICE_ACCEPT_STOP;
    if (canShutdown) 
      _controlsAccepted |= SERVICE_ACCEPT_SHUTDOWN;
    if (canPauseContinue) 
      _controlsAccepted |= SERVICE_ACCEPT_PAUSE_CONTINUE;
  }

  // Service object destructor. 
  ~this()
  {
  }

  // Stop the service.
  void Stop()
  {
    DWORD dwOriginalState = _serviceStatus.dwCurrentState;
    try
      {
	// Tell SCM that the service is stopping.
	SetStatus(SERVICE_STOP_PENDING);

	// Perform service-specific stop operations.
	OnStop();

	// Tell SCM that the service is stopped.
	SetStatus(SERVICE_STOPPED);
      }
    catch (Exception e)
      {
	// Log the error.
	WriteErrorLogEntry(r"Service failed to stop.", e.toString());

	// Set the orginal service status.
	SetStatus(dwOriginalState);
      }
  }


protected:

  // When implemented in a derived class, executes when a Start command is 
  // sent to the service by the SCM or when the operating system starts 
  // (for a service that starts automatically). Specifies actions to take 
  // when the service starts.
  abstract void OnStart(string[] args);

  // When implemented in a derived class, executes when a Stop command is 
  // sent to the service by the SCM. Specifies actions to take when a 
  // service stops running.
  abstract void OnStop();

  // When implemented in a derived class, executes when a Pause command is 
  // sent to the service by the SCM. Specifies actions to take when a 
  // service pauses.
  abstract void OnPause();

  // When implemented in a derived class, OnContinue runs when a Continue 
  // command is sent to the service by the SCM. Specifies actions to take 
  // when a service resumes normal functioning after being paused.
  abstract void OnContinue();

  // When implemented in a derived class, executes when the system is 
  // shutting down. Specifies what should occur immediately prior to the 
  // system shutting down.
  abstract void OnShutdown();

  // Set the service status and report the status to the SCM.
  DWORD SetStatus(DWORD state, 
		  DWORD exitCode = NO_ERROR, 
		  DWORD waitHint = 0)
  {
    _serviceStatus.dwCheckPoint = ((state == SERVICE_RUNNING) || (state == SERVICE_STOPPED))
      ? 0
      : _checkPoint++;
    _serviceStatus.dwCurrentState  = state;
    _serviceStatus.dwWin32ExitCode = exitCode;
    _serviceStatus.dwWaitHint      = waitHint;

    auto result = SetServiceStatus(_serviceStatusHandle, &_serviceStatus);
    if (result == 0) 
      {
	throw new Exception(to!string(GetLastError()));
      }
    return result;
  }

  // Log a message to the Application event log.
  void WriteEventLogEntry(string pMessage, WORD wType)
  {
    auto hEventSource = RegisterEventSource(null, cast (char*) toStringz(_serviceName));
    if (hEventSource)
      {
	LPCSTR[] lpszStrings = 
	  [
	   cast (char*) toStringz(_serviceName),
	   cast (char*) toStringz(pMessage)
	   ];

	ReportEvent(hEventSource,       // Event log handle
		    wType,              // Event type
		    cast (ushort) 0,    // Event category
		    cast (uint) 0,      // Event identifier
		    cast (void*) null,  // No security identifier
		    cast (ushort) 2,    // Size of lpszStrings array
		    cast (uint) 0,      // No binary data
		    lpszStrings.ptr,    // Array of strings
		    cast (void*) null   // No binary data
		    );

	DeregisterEventSource(hEventSource);
      }
  }

  // Log an error message to the Application event log.
  void WriteErrorLogEntry(string pFunction, string exception, DWORD dwError = GetLastError())
  {
    string msg = _serviceName ~ " failed in " ~ pFunction ~ "-" ~ to!string(dwError) ~ "-" ~ exception;
    WriteEventLogEntry(msg, EVENTLOG_ERROR_TYPE);
  }


private:

  // Entry point for the service. It registers the handler function for the 
  // service and starts the service.
  extern(Windows)
  static void ServiceMain(DWORD argc, TCHAR** argv)
  {
    auto mythread = thread_attachThis(); //alert TLS to SCM thread

    if (!_service) _service = cast (ServiceBase) singleton;

    _service._serviceStatus.dwServiceType              = SERVICE_WIN32_OWN_PROCESS;
    _service._serviceStatus.dwCurrentState             = SERVICE_STOPPED;
    _service._serviceStatus.dwControlsAccepted         = _service._controlsAccepted;
    _service._serviceStatus.dwWin32ExitCode            = NO_ERROR;
    _service._serviceStatus.dwServiceSpecificExitCode  = 0;
    _service._serviceStatus.dwCheckPoint               = 0;
    _service._serviceStatus.dwWaitHint                 = 3000;

    Sleep(50); //delay before getting handler

    _service._serviceStatusHandle = RegisterServiceCtrlHandlerEx(cast(char*) toStringz(_service._serviceName),
								 &_service.ServiceControlHandler, null);

    if (!_service._serviceStatusHandle) throw new Exception(to!string(GetLastError()));

    // start the service.
    _service.Start(argc, argv);
  }

  // The function is called by the SCM whenever a control code is sent to  the service.
  extern (Windows)
  static DWORD ServiceControlHandler(DWORD controlCode, DWORD eventType,
				     void* eventData, void* context)
  {
    if (!_service) _service = cast (ServiceBase) singleton;
    switch (controlCode)
      {
      case SERVICE_CONTROL_SHUTDOWN:
	_service.Shutdown();
	break;
      case SERVICE_CONTROL_STOP:
	_service.Stop();
	break;
      case SERVICE_CONTROL_PAUSE: // 2
	_service.Pause();
	break;
      case SERVICE_CONTROL_CONTINUE: // 3
	_service.Continue();
	break;
      case SERVICE_CONTROL_INTERROGATE: // 4
      case SERVICE_CONTROL_SESSIONCHANGE:
      default:
	break;
      }
    return NO_ERROR;
  }

  // start the service - inherited must implement
  void Start(DWORD argc, TCHAR** argv)
  {
    try
      {
	// Tell SCM that the service is starting.
	_serviceStatus.dwControlsAccepted = 0; //accept no controls while pending
	SetStatus(SERVICE_START_PENDING);

	//string arg1 = to!string(argv[0]);
	// Perform service-specific initialization.
	string[] args = null; // cast (string[]) toStringz(argv);
	if (argc > 0)
	  {
	    args = new string[argc];
	    for (int i = 0; i < argc; i++) args[i] = to!string(argv[i]);
	  }

	OnStart(args);

	// Tell SCM that the service is started.
	_serviceStatus.dwControlsAccepted = _controlsAccepted;
	SetStatus(SERVICE_RUNNING);
      }
    catch (Exception e)
      {
	// Log the error.
	WriteErrorLogEntry(r"Service failed to start.", e.toString());

	// Set the service status to be stopped.
	SetStatus(SERVICE_STOPPED);
      }
  }

  // Pause the service.
  void Pause()
  {
    try
      {
	// Tell SCM that the service is pausing.
	SetStatus(SERVICE_PAUSE_PENDING);

	// Perform service-specific pause operations.
	OnPause();

	// Tell SCM that the service is paused.
	SetStatus(SERVICE_PAUSED);
      }
    catch (Exception e)
      {
	// Log the error.
	WriteErrorLogEntry(r"Service failed to pause", e.toString());

	// Tell SCM that the service is still running.
	SetStatus(SERVICE_RUNNING);
      }
  }

  // Resume the service after being paused.
  void Continue()
  {
    try
      {
	// Tell SCM that the service is resuming.
	SetStatus(SERVICE_CONTINUE_PENDING);

	// Perform service-specific continue operations.
	OnContinue();

	// Tell SCM that the service is running.
	SetStatus(SERVICE_RUNNING);
      }
    catch (Exception e)
      {
	// Log the error.
	WriteErrorLogEntry(r"Service failed to resume (continue).", e.toString());

	// Tell SCM that the service is still paused.
	SetStatus(SERVICE_PAUSED);
      }
  }

  // Execute when the system is shutting down.
  void Shutdown()
  {
    try
      {
	// Perform service-specific shutdown operations.
	OnShutdown();

	// Tell SCM that the service is stopped.
	SetStatus(SERVICE_STOPPED);
      }
    catch (Exception e)
      {
	// Log the error.
	WriteErrorLogEntry(r"Service failed to shut down.", e.toString());
      }
  }
}