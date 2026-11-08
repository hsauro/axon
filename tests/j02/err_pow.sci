#! error: OverflowError
__jit_mode("on")
function big(a: int): int
  return a ^ 40
end
print(big(3) == 0)
