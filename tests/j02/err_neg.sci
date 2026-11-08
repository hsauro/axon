#! error: OverflowError
__jit_mode("on")
function neg(a: int): int
  return -a
end
println(neg(5))
println(neg(-9223372036854775807 - 1))
