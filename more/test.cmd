@echo off

set DFLAGS=

REM Generate gocumentation
set DFLAGS=%DFLAGS% -D

REM Create DDox JSON file
REM set DFLAGS=%DFLAGS% -D -X -Xfdocs.json

REM Perform code coverage
REM set DFLAGS=%DFLAGS% -cov

REM Execute unit tests
set DFLAGS=%DFLAGS% -unittest

REM Debug version
REM set DFLAGS=%DFLAGS% -debug

dmd -ofunittest.exe -main %DFLAGS% -I.. sdl.d sdlreflection.d common.d utf8.d
if %errorlevel% neq 0 goto exit


unittest.exe

:exit