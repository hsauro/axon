function get(v: vector{real}, i: int): real
  return v[i] + v[end]
end

function put(A: matrix{real}, x: int)
  A[2, end] = x
  return A
end

function each(v: vector{int}): int
  s = 0
  for x in v
    s = s + x
  end
  return s
end

function axpy(a: real, x: vector{real}, y: vector{real}): vector{real}
  return a * x + y
end

function plain(v: vector)
  return v
end
