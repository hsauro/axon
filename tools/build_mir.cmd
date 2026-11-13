@echo off
rem Fetches MIR (a pinned commit) into third_party\mir and builds lib\win64\mir.dll
rem with MSVC 2022 through tools\mir\CMakeLists.txt. Needs git and CMake.
rem
rem The commit is master after v1.0.0 (2026-10): v1.0.0's optimiser (level 2)
rem compiled some large functions wrongly, such as the rate laws of a 68-reaction
rem model; fixed upstream (out-of-bounds write in try_spilled_reg_mem and
rem out-of-SSA lost copies, among others). tools\build_mir_mac.sh uses the same.
setlocal
set MIR_COMMIT=dc2c763f1c8bc746102ce87933d866335f9e6c06
set ROOT=%~dp0..
if not exist "%ROOT%\third_party\mir\mir.c" (
  git clone https://github.com/vnmakarov/mir.git "%ROOT%\third_party\mir" || exit /b 1
)
git -C "%ROOT%\third_party\mir" fetch -q origin master || exit /b 1
git -C "%ROOT%\third_party\mir" checkout -q %MIR_COMMIT% || exit /b 1
cmake -S "%ROOT%\tools\mir" -B "%ROOT%\third_party\mir-build" -G "Visual Studio 17 2022" -A x64 || exit /b 1
cmake --build "%ROOT%\third_party\mir-build" --config Release || exit /b 1
copy /y "%ROOT%\third_party\mir-build\Release\mir.dll" "%ROOT%\lib\win64\mir.dll" || exit /b 1
echo mir.dll built from MIR %MIR_COMMIT%
