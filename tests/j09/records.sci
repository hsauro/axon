# Records in compiled code (J9). Each line: the compiled result, whether
# the interpreter gives the same, the array copies the compiled call made,
# whether the interpreter made as many, and whether the function compiled.

function both(f, x)
  __jit_mode("on")
  c = __copies()
  a = f(x)
  ca = __copies() - c
  __jit_mode("off")
  c = __copies()
  b = f(x)
  cb = __copies() - c
  __jit_mode("on")
  println(string(a), string(a) == string(b), ca, ca == cb, __jit_compiled(f))
end

record Params
  a: real
  b: real
  n: int
end

record Pair
  p: Params
  on: bool
end

# A right-hand side reading a parameter record.
function lv(p)
  y = [10.0; 5.0]
  return [p.a * y[1] - p.b * y[1] * y[2]; p.b * y[1] * y[2] - p.a * y[2]]
end
both(lv, Params(1.0, 0.1, 2))

# State kept in a record, stepped in a loop; the record grows no fields.
function simulate(n)
  s = {t: 0.0, y: ones(3), steps: 0}
  for k in 1:n
    s.t = s.t + 0.1
    for i in 1:length(s.y)
      s.y[i] = s.y[i] * 0.5 + s.t
    end
    s.steps = s.steps + 1
  end
  return s
end
both(simulate, 4)

# Literals and constructors, by position and by keyword; declared field
# types coerce (an int for a real field).
function make(x)
  q = Params(x, 2, 7)
  r = Params(n = 1, b = x, a = 3)
  return {q: q, r: r, sum: q.a + q.b + r.a + q.n}
end
both(make, 1.5)

# Nested records: reads, writes and constructors of a record in a record.
function nest(x)
  pr = Pair(Params(x, x, 1), true)
  pr.p.a = pr.p.a * 2.0
  if pr.on
    pr.p.n = pr.p.n + 10
  end
  pr.on = false
  return pr
end
both(nest, 0.25)

# Copy-on-write: a record shared with another variable is copied before a
# write, and so is its array, once.
function shared(n)
  s = {y: zeros(n), k: 1}
  t = s
  s.k = 2
  s.y[1] = 5.0
  return {s: s, t: t}
end
both(shared, 3)

# A record parameter written in the function: the caller's is unchanged.
function bump(r)
  r.y[2] = r.y[2] + 1.0
  r.k = r.k + 1
  return r.k + r.y[2]
end
outer = {y: [1.0; 2.0; 3.0], k: 10}
both(bump, outer)
println(outer.k, outer.y[2])

# A record unique to the function: writes in place, no copies.
function local_only(n)
  s = {y: zeros(n)}
  for i in 1:n
    s.y[i] = i
  end
  return s.y
end
both(local_only, 4)

# A declared record's field widens a narrower number when written.
function widen(x)
  p = Params(1.0, 2.0, 3)
  p.a = 4
  p.b = x
  return p
end
both(widen, true)

# Records passed to compiled and interpreted callees, a field's array as an
# argument, and records returned.
function norm2(v: vector{real}): real
  s = 0.0
  for x in v
    s = s + x * x
  end
  return s
end
function scale(r, f)
  r.y = r.y * f
  return r
end
function chain(n)
  s = {y: ones(n), name_len: 4}
  s = scale(s, 2.0)
  return norm2(s.y) + s.name_len
end
both(chain, 3)

# A whole record read from outside, passed on.
cfg = {k: 3.0, y: [1.0; 2.0]}
function use_cfg(x)
  return x * cfg.k + norm2(cfg.y)
end
both(use_cfg, 2.0)

# size and length through a path, a matrix in a record.
function mat(n)
  s = {M: zeros(n, n + 1)}
  for i in 1:size(s.M, 1)
    for j in 1:size(s.M, 2)
      s.M[i, j] = i * 10 + j
    end
  end
  [r, c] = size(s.M)
  return s.M[n, n + 1] + r + c
end
both(mat, 2)

# Shapes the JIT rejects, with the interpreter's result.
function grows(x)
  s = {a: x}
  s.b = x + 1.0
  return s
end
both(grows, 1.0)

function changes(x)
  s = {a: x}
  s.a = 2
  return s
end
both(changes, 1.5)
