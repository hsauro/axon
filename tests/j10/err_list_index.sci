#! error: IndexError
__jit_mode("on")
function nth(l, k: int): real
  return l[k] * 2.0
end
function outer(n: int): real
  l = {}
  for k in 1:n
    l = append(l, k * 1.0)
  end
  return nth(l, n + 1)
end
outer(3)
