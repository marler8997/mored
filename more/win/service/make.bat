set MORE=..\..\..
set DSOURCE=..\..\..\..\dsource-bindings

dmd -I%MORE% -I%DSOURCE% -main -unittest installer.d %MORE%\more\win\common.d %DSOURCE%\win32\winbase.d %DSOURCE%\win32\winnt.d %DSOURCE%\win32\winsvc.d
