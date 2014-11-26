set DSOURCE=..\..\..\dsource-bindings

REM dmd -I%DSOURCE% -main -unittest installer.d %DSOURCE%\win32\winbase.d %DSOURCE%\win32\winnt.d %DSOURCE%\win32\winsvc.d

dmd -I%DSOURCE% -main -unittest common.d %DSOURCE%\win32\winbase.d %DSOURCE%\win32\winnt.d %DSOURCE%\win32\winsvc.d
