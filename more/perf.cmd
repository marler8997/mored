set FLAGS=-O -noboundscheck -inline
#set FLAGS=-O -noboundscheck
#set FLAGS=-noboundscheck

dmd %FLAGS% performance.d utf8.d
if NOT %ERRORLEVEL% == 0 GOTO EXIT

.\performance.exe

:EXIT