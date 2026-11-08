#! error: OverflowError
__jit_mode("on")
function add(a: int, b: int): int
  return a + b
end
println(add(1, 2))
println(add(9223372036854775807, 1))
