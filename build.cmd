@echo off
rem Build the axon interpreter for Win64 with RAD Studio 37.0 (Delphi 13).
rem   build            Debug build  -> Win64\Debug\axon.exe
rem   build Release    Release build -> Win64\Release\axon.exe
rem Also builds the native test library used by the M9 tests (tests\m09\bin).
setlocal
set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Debug
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild "%~dp0axon.dproj" /t:Build /p:Config=%CONFIG% /p:Platform=Win64 /nologo /v:minimal
if errorlevel 1 exit /b %ERRORLEVEL%
if not exist "%~dp0tests\m09\bin\dcu" mkdir "%~dp0tests\m09\bin\dcu"
dcc64 -Q -B -NSSystem;Winapi -E"%~dp0tests\m09\bin" -NU"%~dp0tests\m09\bin\dcu" "%~dp0tests\m09\native\axontest.dpr"
exit /b %ERRORLEVEL%
