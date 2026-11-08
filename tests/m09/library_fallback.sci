extern "bin/axontest"
  function add_i32(a: int32, b: int32): int32
end
extern "no_such_library"
  function never_called()
end
println(add_i32(20, 22))
