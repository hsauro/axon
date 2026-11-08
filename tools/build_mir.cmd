@echo off
rem Fetches MIR (pinned tag) into third_party\mir and builds lib\win64\mir.dll
rem with MSVC 2022 through tools\mir\CMakeLists.txt. Needs git and CMake.
setlocal
set MIR_TAG=v1.0.0
set ROOT=%~dp0..
if not exist "%ROOT%\third_party\mir\mir.c" (
  git clone --depth 1 --branch %MIR_TAG% https://github.com/vnmakarov/mir.git "%ROOT%\third_party\mir" || exit /b 1
)
cmake -S "%ROOT%\tools\mir" -B "%ROOT%\third_party\mir-build" -G "Visual Studio 17 2022" -A x64 || exit /b 1
cmake --build "%ROOT%\third_party\mir-build" --config Release || exit /b 1
copy /y "%ROOT%\third_party\mir-build\Release\mir.dll" "%ROOT%\lib\win64\mir.dll" || exit /b 1
echo mir.dll built from MIR %MIR_TAG%
