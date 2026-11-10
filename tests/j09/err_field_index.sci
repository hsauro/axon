#! error: IndexError
__jit_mode("on")
function setk(s, k: int)
  s.y[k] = 1.0
  return s
end
function outer(n: int): real
  s = {y: zeros(n), t: 0.0}
  s = setk(s, n + 1)
  return s.t
end
outer(3)
