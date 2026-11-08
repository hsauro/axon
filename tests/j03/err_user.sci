#! error: UserError
__jit_mode("on")
function check(n: int): int
  if n < 0
    error("negative input")
  end
  return n
end
println(check(3))
check(-1)
