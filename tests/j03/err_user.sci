#! error: UserError
__jit_mode("on")
function check(n: int): int
  if n < 0
    error("negative input")
  end
  return n
end
print(check(3))
check(-1)
