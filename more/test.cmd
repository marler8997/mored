@echo off

set DFLAGS=

REM Generate gocumentation
set DFLAGS=%DFLAGS% -D

REM Perform code coverage
REM set DFLAGS=-cov

REM Perform code coverage
set DFLAGS=-unittest

dmd -ofunittest.exe -main %DFLAGS% -I.. sdl.d common.d utf8.d
if %errorlevel% neq 0 goto exit


unittest.exe

:exit