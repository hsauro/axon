@echo off
rem Runs the JIT benchmarks (bench\*.sci) and prints the best time per call
rem of each kernel, with a check that its result is right (true).
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
for %%f in (*.sci) do "%AXON%" "%%f" || (popd & exit /b 1)
popd
