## The loop micro-benchmarks behind the manual's appendix "Speed compared
## with Python": the cost of one loop iteration with a simple body,
## interpreted and compiled. Run through bench/loops_vs_python.py, which
## prints them beside the same loops in Python.

import time

function empty_loop(n: int): int
  for k in 1:n
  end
  return n
end

function assign_loop(n: int): int
  x = 0
  for k in 1:n
    x = k
  end
  return x
end

function arith_loop(n: int): real
  x = 0.0
  for k in 1:n
    x = x + k * 2.0
  end
  return x
end

function inc(x: real): real
  return x + 1.0
end

function call_loop(n: int): real
  x = 0.0
  for k in 1:n
    x = inc(x)
  end
  return x
end

function array_loop(n: int): real
  v = zeros(n)
  for k in 1:n
    v[k] = v[k] + 1.0
  end
  return v[n]
end

function while_loop(n: int): int
  k = 0
  while k < n
    k = k + 1
  end
  return k
end

function row(name, g, n)
  __jit_mode("off")
  ti = time.bench(g).best
  __jit_mode("on")
  g()
  tc = time.bench(g).best
  println(name + "\t" + string(ti / n * 1e9) + "\t" + string(tc / n * 1e9))
end

n = 1000000
row("empty for loop", function() return empty_loop(n) end, n)
row("while loop, k = k + 1", function() return while_loop(n) end, n)
row("assignment x = k", function() return assign_loop(n) end, n)
row("x = x + k * 2.0", function() return arith_loop(n) end, n)
row("function call x = inc(x)", function() return call_loop(n) end, n)
row("array v[k] = v[k] + 1.0", function() return array_loop(n) end, n)
