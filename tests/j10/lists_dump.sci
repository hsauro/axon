# Lists in JIR (J10): {} then appends, in place; literals; reads, writes and
# length; for over a list; a list in a record.

function build(n: int)
  l = {}
  for k in 1:n
    l = append(l, k * 0.5)
  end
  return l
end

function sum_first(n: int): real
  l = build(n)
  l[1] = l[1] + 1.0
  s = 0.0
  for x in l
    s = s + x
  end
  t = {xs: l, k: 2}
  return s + t.xs[t.k] + length(t.xs)
end

function lit(x: real)
  return {x, 2.0 * x}
end
