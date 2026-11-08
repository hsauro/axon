@echo off
rem Run the conformance tests with the Debug build.
rem   test             all milestones
rem   test -v tests\m03   one milestone, listing passes too
rem   test -jit        all milestones three times: JIT off, on and forced
setlocal
set AXON=%~dp0Win64\Debug\axon.exe
if not exist "%AXON%" (
  echo axon.exe not found; run build.cmd first
  exit /b 2
)
if "%~1"=="-jit" goto alljit
if "%~1"=="" (
  "%AXON%" test "%~dp0tests"
) else (
  "%AXON%" test %*
)
exit /b %ERRORLEVEL%

:alljit
set FAILED=0
for %%m in (off on force) do (
  echo == JIT %%m
  set "AXON_JIT=%%m"
  "%AXON%" test "%~dp0tests" || set FAILED=1
)
exit /b %FAILED%
