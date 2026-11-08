function scale(x, k)
  return x * k
end

function both(a: int, b: real): real
  return scale(a, 2) + scale(b, 2)
end

function first(v)
  return v[1]
end

function use(A: matrix{real}, w: vector{int}): real
  return first(w) + A[1, 1]
end
