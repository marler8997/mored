@call rdmd -debug -g gendeps.d checked
@if ERRORLEVEL 1 exit /B 1
@call rdmd -debug -g go.d %*

