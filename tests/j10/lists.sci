# Lists in compiled code (J10). Each line: the compiled result, whether the
# interpreter gives the same, the array copies the compiled call made,
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

# {} then appends: the empty literal takes the element type of the appends.
function build(n)
  l = {}
  for k in 1:n
    l = append(l, k * 0.5)
  end
  return l
end
both(build, 5)

# Reading: for over the elements, an index, end and length.
function total(l)
  s = 0.0
  for x in l
    s = s + x
  end
  return s + l[2] + l[end] + length(l)
end
both(total, {1.0, 2.0, 4.0})

# A list literal of one type, and append making a new list.
function lit(x)
  a = {x, x + 1.0}
  b = append(a, x * 2.0)
  return {a: a, b: b}
end
both(lit, 3.0)

# Copy-on-write: a list shared with another variable, or passed in, is
# copied before a write or an append; the caller's is unchanged.
function shared(x)
  l = {1.0, 2.0}
  m = l
  l[1] = x
  l = append(l, x)
  return {l: l, m: m}
end
both(shared, 9.0)

function param(l)
  l[1] = 0.0
  l = append(l, 7.0)
  return length(l)
end
outer = {1.0, 2.0, 3.0}
both(param, outer)
println(outer)

# Lists of records, of vectors and of lists.
function recs(n)
  out = {}
  for k in 1:n
    out = append(out, {t: k * 1.0, y: zeros(2)})
  end
  s = 0.0
  for r in out
    s = s + r.t + length(r.y)
  end
  return s + out[2].t
end
both(recs, 4)

function vecs(n)
  vs = {}
  for k in 1:n
    vs = append(vs, k * ones(k))
  end
  return vs[n][1] + length(vs[n]) + length(vs)
end
both(vecs, 3)

function triangle(n)
  rows = {}
  for k in 1:n
    row = {}
    for j in 1:k
      row = append(row, j)
    end
    rows = append(rows, row)
  end
  return rows
end
both(triangle, 3)

# A list in a record: read and written through the field.
function in_record(x)
  s = {items: {1.0, 2.0}, k: 0}
  s.items[2] = x
  s.k = length(s.items)
  return s.items[1] + s.items[2] + s.k
end
both(in_record, 5.0)

# An empty list argument matches code compiled for any list type.
function count_big(l)
  n = 0
  for x in l
    if x > 1.0
      n = n + 1
    end
  end
  return n
end
both(count_big, {0.5, 2.0, 3.0})
both(count_big, {})

# Shapes the JIT rejects, with the interpreter's result.
function mixed(x)
  return {x, 1}
end
both(mixed, 2.0)

function mixes(x)
  l = {1.0, 2.0}
  l[1] = 3
  return l
end
both(mixes, 0)
