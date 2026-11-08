#! error: ArgumentError
__jit_mode("on")
function count(h: int): int
  n = 0
  for k in 1:h:5
    n = n + 1
  end
  return n
end
println(count(2))
println(count(0))
