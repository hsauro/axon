import mathpkg
p = __native_library("testlib")
print(p == "win/testlib.dll" or p == "mac/libtestlib.dylib" or p == "linux/libtestlib.so")
print(__native_library("unknown"))
print(mathpkg.native())
