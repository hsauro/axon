#! error: IndexError
__jit_mode("on")
function setk(v: vector{real}, k: int): vector{real}
  v[k] = 1.0
  return v
end
function outer(n: int): real
  w = zeros(n)
  w = setk(w, n + 1)
  return w[1]
end
outer(3)
