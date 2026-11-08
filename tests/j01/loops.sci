function sum_odd(n: int): int
  s = 0
  for k in 1:2:n
    s = s + k
  end
  return s
end

function trapezoid(a: real, b: real, m: int): real
  h = (b - a) / m
  s = 0.0
  for x in a:h:b
    s = s + x
  end
  return s * h
end
