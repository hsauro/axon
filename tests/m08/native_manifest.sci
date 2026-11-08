import mathpkg
p = __native_library("testlib")
println(p == "win/testlib.dll" or p == "mac/libtestlib.dylib" or p == "linux/libtestlib.so")
println(__native_library("unknown"))
println(mathpkg.native())
