# Builds mir.dll (Windows) or libmir.dylib (macOS) from MIR's core only:
# the MIR API, interpreter and generator (mir.c, mir-gen.c); no C front end.
# Axon's shim over the API (src/native/axmir.c) is compiled in as well.
# The sources are fetched by tools/build_mir.cmd into third_party/mir.
cmake_minimum_required(VERSION 3.15)
project(axon_mir C)

set(MIR_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/mir")
add_library(mir SHARED "${MIR_SRC}/mir.c" "${MIR_SRC}/mir-gen.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../src/native/axmir.c")
target_include_directories(mir PRIVATE "${MIR_SRC}")

if(WIN32)
  # Export every function (mir.h has no export macros), and link the C
  # runtime statically so mir.dll needs no Visual C++ redistributable.
  set_target_properties(mir PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS TRUE
    MSVC_RUNTIME_LIBRARY "MultiThreaded")
else()
  target_compile_options(mir PRIVATE -std=gnu11 -fsigned-char -fPIC)
endif()
