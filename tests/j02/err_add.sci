#! error: OverflowError
__jit_mode("on")
function add(a: int, b: int): int
  return a + b
end
print(add(1, 2))
print(add(9223372036854775807, 1))
