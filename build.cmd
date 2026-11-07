@echo off
rem Build the axon interpreter for Win64 with RAD Studio 37.0 (Delphi 13).
rem   build            Debug build  -> Win64\Debug\axon.exe
rem   build Release    Release build -> Win64\Release\axon.exe
setlocal
set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Debug
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild "%~dp0axon.dproj" /t:Build /p:Config=%CONFIG% /p:Platform=Win64 /nologo /v:minimal
exit /b %ERRORLEVEL%
