@echo off
rem Runs the JIT benchmarks (bench\run.sci): each kernel timed interpreted
rem and compiled (best of 5 per call), with a check that both agree.
rem   bench            uses Win64\Release\axon.exe (build Release first)
rem   bench Debug      uses Win64\Debug\axon.exe
setlocal
set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Release
set AXON=%~dp0Win64\%CONFIG%\axon.exe
if not exist "%AXON%" (
  echo bench: %AXON% not found; run build %CONFIG% first
  exit /b 2
)
pushd "%~dp0bench"
"%AXON%" run.sci
set RESULT=%ERRORLEVEL%
popd
exit /b %RESULT%
