@rund -debug -g gendeps.d checked
@if ERRORLEVEL 1 exit /B 1
@rund -debug -g go.d %*

