function sq(x: real): real
  return x * x
end

function norm(x: real, y: real): real
  return sqrt(sq(x) + sq(y))
end

function report(n: int)
  println("n =", n, floor(2.5))
  if n < 0
    error("negative")
  end
end

function pair(a: int)
  return a, a + 1
end

function use_pair(a: int): int
  [p, q] = pair(a)
  return p * q
end

function legacy(x)
  s = 1i
  return x
end

function wrap(x: real): real
  legacy(x)
  return x
end
