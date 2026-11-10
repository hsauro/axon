# Records in JIR (J9): construction, field reads and writes through paths,
# element access through a field, and specialisation on a record's shape.

record P
  a: real
  n: int
end

function area(r)
  return r.w * r.h
end

function grow(s, h: real)
  s.t = s.t + h
  s.y[1] = s.y[1] * 2.0
  s.q.n = s.q.n + 1
  return s
end

function driver(n: int): real
  b = {w: 2.0, h: 3.0}
  q = P(1.5, n)
  s = {t: 0.0, y: zeros(n), q: q}
  s = grow(s, 0.5)
  return area(b) + s.q.a + length(s.y)
end

function kw(x: real)
  return P(n = 2, a = x)
end

function adds(r: real)
  s = {a: r}
  s.b = 1.0
  return s
end
