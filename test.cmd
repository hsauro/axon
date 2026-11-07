@echo off
rem Run the conformance tests with the Debug build.
rem   test             all milestones
rem   test -v tests\m03   one milestone, listing passes too
setlocal
set AXON=%~dp0Win64\Debug\axon.exe
if not exist "%AXON%" (
  echo axon.exe not found; run build.cmd first
  exit /b 2
)
if "%~1"=="" (
  "%AXON%" test "%~dp0tests"
) else (
  "%AXON%" test %*
)
exit /b %ERRORLEVEL%
