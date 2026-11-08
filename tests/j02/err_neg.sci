#! error: OverflowError
__jit_mode("on")
function neg(a: int): int
  return -a
end
print(neg(5))
print(neg(-9223372036854775807 - 1))
