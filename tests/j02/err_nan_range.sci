#! error: ArgumentError
__jit_mode("on")
function count(a: real): int
  n = 0
  for x in a:1.0:5.0
    n = n + 1
  end
  return n
end
count(0.0 / 0.0)
