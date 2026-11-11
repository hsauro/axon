#! error: IndexError
function setk(v: vector{real}, k: int): vector{real}
  v[k] = 1.0
  return v
end
w = zeros(3)
for k in 1:4
  w = setk(w, k)
end
