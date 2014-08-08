@echo off

dmd -ofunittest.exe -main -unittest -I.. sdl.d common.d utf8.d
if %errorlevel% neq 0 goto exit


unittest.exe

:exit