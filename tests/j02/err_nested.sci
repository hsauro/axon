#! error: OverflowError
__jit_mode("on")
function f(n: int): int
  s = 1
  for k in 1:n
    if k > 2
      s = s * 1000000000
    end
  end
  return s
end
x = f(3)
y = f(5)
