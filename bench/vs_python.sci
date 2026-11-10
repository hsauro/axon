## Axon's half of the comparison with Python (bench/vs_python.py, which runs
## this file and prints both side by side). Each kernel is timed with
## time.bench (best of 5 runs per call); loop kernels are timed interpreted
## and compiled. Each line is: name, interpreted s, compiled s, check value.

import time
import ode
import linalg

# ---------------------------------------------------------------- loops

function fib(n: int): int
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

function harmonic(n: int): real
  s = 0.0
  for k in 1:n
    s = s + 1.0 / k
  end
  return s
end

function sieve(n: int): int
  flags = ones(n)
  flags[1] = 0.0
  count = 0
  for i in 2:n
    if flags[i] == 1.0
      count = count + 1
      j = i * i
      while j <= n
        flags[j] = 0.0
        j = j + i
      end
    end
  end
  return count
end

function escape(cr: real, ci: real, maxit: int): int
  zr = 0.0
  zi = 0.0
  k = 0
  while k < maxit and zr * zr + zi * zi <= 4.0
    t = zr * zr - zi * zi + cr
    zi = 2.0 * zr * zi + ci
    zr = t
    k = k + 1
  end
  return k
end

function mandel(n: int, maxit: int): int
  total = 0
  for i in 1:n
    for j in 1:n
      total = total + escape(-2.0 + 2.5 * (j - 1) / n, -1.25 + 2.5 * (i - 1) / n, maxit)
    end
  end
  return total
end

function matmul(A, B)
  n = size(A, 1)
  m = size(B, 2)
  p = size(A, 2)
  C = zeros(n, m)
  for i in 1:n
    for j in 1:m
      s = 0.0
      for k in 1:p
        s = s + A[i, k] * B[k, j]
      end
      C[i, j] = s
    end
  end
  return C
end

function nbody(steps: int): real
  x = [0.0; 4.84; 8.34; 12.89; 15.38]
  y = [0.0; -1.16; 4.12; -15.11; -25.92]
  z = [0.0; -0.10; -0.40; -0.22; 0.18]
  vx = [0.0; 0.606; -1.010; 1.083; 0.979]
  vy = [0.0; 2.812; 1.825; 0.869; 0.595]
  vz = [0.0; -0.025; 0.008; -0.010; -0.035]
  m = [39.47; 0.0377; 0.0113; 0.0017; 0.0020]
  n = 5
  dt = 0.01
  for s in 1:steps
    for i in 1:n
      for j in i + 1:n
        dx = x[i] - x[j]
        dy = y[i] - y[j]
        dz = z[i] - z[j]
        d2 = dx * dx + dy * dy + dz * dz
        mag = dt / (d2 * sqrt(d2))
        vx[i] = vx[i] - dx * m[j] * mag
        vy[i] = vy[i] - dy * m[j] * mag
        vz[i] = vz[i] - dz * m[j] * mag
        vx[j] = vx[j] + dx * m[i] * mag
        vy[j] = vy[j] + dy * m[i] * mag
        vz[j] = vz[j] + dz * m[i] * mag
      end
    end
    for i in 1:n
      x[i] = x[i] + dt * vx[i]
      y[i] = y[i] + dt * vy[i]
      z[i] = z[i] + dt * vz[i]
    end
  end
  e = 0.0
  for i in 1:n
    e = e + 0.5 * m[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i])
    for j in i + 1:n
      dx = x[i] - x[j]
      dy = y[i] - y[j]
      dz = z[i] - z[j]
      e = e - m[i] * m[j] / sqrt(dx * dx + dy * dy + dz * dz)
    end
  end
  return e
end

# A deterministic, well-conditioned n by n matrix, the same as Python's:
# sin(0.37 i j + shift) with i, j from 0, plus n on the diagonal.
function test_matrix(n, shift)
  A = zeros(n, n)
  for i in 1:n
    for j in 1:n
      A[i, j] = sin(0.37 * (i - 1) * (j - 1) + shift)
    end
    A[i, i] = A[i, i] + n
  end
  return A
end

# ---------------------------------------------------------------- lists, text

function build_list(n)
  l = {}
  for k in 1:n
    l = append(l, k)
  end
  return length(l)
end

function dict_words(n)
  d = dict()
  for k in 1:n
    d["w" + string(k)] = k
  end
  total = 0
  for k in 1:n
    total = total + d["w" + string(k)]
  end
  return total
end

function split_join(text)
  return length(join(split(text), ","))
end

# ---------------------------------------------------------------- driver

function report(name, g, both)
  if both
    __jit_mode("off")
    c = g()
    ti = time.bench(g).best
    __jit_mode("on")
    g()
    tc = time.bench(g).best
  else
    c = g()
    ti = time.bench(g).best
    tc = ti
  end
  println(name + "\t" + string(ti) + "\t" + string(tc) + "\t" + string(c))
end

A100 = test_matrix(100, 0)
B100 = test_matrix(100, 1)
report("fib(25)", function() return fib(25) end, true)
report("harmonic(1e6)", function() return harmonic(1000000) end, true)
report("sieve(1e6)", function() return sieve(1000000) end, true)
report("mandel(100, 100)", function() return mandel(100, 100) end, true)
report("matmul 100x100 loops", function() return sum(matmul(A100, B100)) end, true)
report("nbody(10000)", function() return nbody(10000) end, true)

A = test_matrix(500, 0)
B = test_matrix(500, 1)
b = A[:, 1]
v = linspace(0.0, 1.0, 1000000)
# The library kernels return one element as their check, so that the
# timing is of the operation alone.
report("A * B 500x500 (BLAS)", function() return (A * B)[1, 1] end, false)
report("A \\ b 500 (LAPACK)", function() return (A \ b)[1] end, false)
A200 = A[1:200, 1:200] + A[1:200, 1:200]'
report("eig 200x200", function() return max(linalg.eig(A200)) end, false)
report("exp(v), 1e6", function() return exp(v)[end] end, false)
report("v .* v + 2 * v, 1e6", function() return (v .* v + 2.0 * v)[end] end, false)
report("sum(v), 1e6", function() return sum(v) end, false)
w = sin(linspace(0.0, 1000.0, 1000000))
report("sort 1e6", function() return sort(w)[500000] end, false)

lv = function(t, y) return [y[1] - 0.1 * y[1] * y[2]; 0.075 * y[1] * y[2] - 1.5 * y[2]] end
rob = function(t, y)
  return [-0.04 * y[1] + 1e4 * y[2] * y[3]; 0.04 * y[1] - 1e4 * y[2] * y[3] - 3e7 * y[2]^2; 3e7 * y[2]^2]
end
report("ode RK45 Lotka-Volterra", function() return ode.solve(lv, [10.0; 5.0], [0, 50], rtol = 1e-8).y[1, end] end, false)
report("ode BDF Robertson", function()
  return ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf", rtol = 1e-8, atol = 1e-12).y[1, end]
end, false)

report("list append 1e5", function() return build_list(100000) end, true)
report("dict 1e5 words", function() return dict_words(100000) end, true)
words = repeat("alpha beta gamma delta ", 50000)
report("split + join 2e5 words", function() return split_join(words) end, false)
