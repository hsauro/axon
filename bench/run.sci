## The JIT benchmarks (doc/Axon-JIT-Plan.md, J8): each kernel timed
## interpreted and compiled with time.bench (best of 5 runs, per call), with
## a check that both give the same result. Run with bench.cmd.

import time
import ode

# ---------------------------------------------------------------- kernels

## Recursive Fibonacci: call overhead and int arithmetic.
function fib(n: int): int
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

## A scalar loop: a partial sum of the harmonic series.
function harmonic(n: int): real
  s = 0.0
  for k in 1:n
    s = s + 1.0 / k
  end
  return s
end

## Vector reads and writes: the sieve of Eratosthenes.
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

## Real arithmetic and calls: points of the Mandelbrot set.
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

## A naive triple-loop matrix product (compare BLAS through *).
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

## N-body: five bodies under gravity, symplectic Euler; returns the energy.
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

## ODE solves: the solvers' loops are native either way; the JIT compiles
## the right-hand side.
p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}
lv = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2]; p.c*y[1]*y[2] - p.d*y[2]]
end
rob = function(t, y)
  return [-0.04*y[1] + 1e4*y[2]*y[3]; 0.04*y[1] - 1e4*y[2]*y[3] - 3e7*y[2]^2; 3e7*y[2]^2]
end
function lv_rk45()
  return ode.solve(lv, [10.0; 5.0], [0, 50], rtol = 1e-8).y
end
function rob_bdf()
  return ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf", rtol = 1e-8, atol = 1e-12).y
end

## Records (J9): a simulation step that keeps its state in a record.
function record_steps(n: int): real
  s = {t: 0.0, y: ones(10), steps: 0}
  for k in 1:n
    s.t = s.t + 0.01
    for i in 1:length(s.y)
      s.y[i] = s.y[i] + 0.01 * (s.t - s.y[i])
    end
    s.steps = s.steps + 1
  end
  return s.y[10] + s.steps
end

## An ODE whose right-hand side reads a parameter record, passed with params.
record LVParams
  a: real
  b: real
  c: real
  d: real
end
lv_rec = function(t, y, q)
  return [q.a*y[1] - q.b*y[1]*y[2]; q.c*y[1]*y[2] - q.d*y[2]]
end
function lv_params()
  return ode.solve(lv_rec, [10.0; 5.0], [0, 50], rtol = 1e-8,
                   params = LVParams(1.0, 0.1, 0.075, 1.5)).y
end

## Lists (J10): build a list of reals by appending, then sum it.
function list_build_sum(n: int): real
  l = {}
  for k in 1:n
    l = append(l, k * 0.5)
  end
  s = 0.0
  for x in l
    s = s + x
  end
  return s
end

## A list of records (particles), stepped and summed.
function particles(n: int, steps: int): real
  ps = {}
  for k in 1:n
    ps = append(ps, {x: k * 1.0, v: 0.5})
  end
  for s in 1:steps
    for k in 1:length(ps)
      p = ps[k]
      ps[k] = {x: p.x + 0.01 * p.v, v: p.v * 0.999}
    end
  end
  total = 0.0
  for p in ps
    total = total + p.x
  end
  return total
end

# ---------------------------------------------------------------- driver

function pad(s, w)
  while length(s) < w
    s = s + " "
  end
  return s
end

function lpad(s, w)
  while length(s) < w
    s = " " + s
  end
  return s
end

# Times g() interpreted and compiled; prints a table row.
function row(name, g)
  __jit_mode("off")
  a = g()
  ti = time.bench(g).best
  __jit_mode("on")
  b = g()
  tc = time.bench(g).best
  same = isequal(a, b)
  println(pad(name, 30), lpad(time.format(ti), 10), lpad(time.format(tc), 10),
    lpad(string(round(ti / tc)) + "x", 8), "  ", same)
end

A = rand(60, 60)
B = rand(60, 60)
println(pad("kernel", 30), lpad("interp.", 10), lpad("compiled", 10), lpad("speed-up", 8), "  same")
row("fib(22)", function() return fib(22) end)
row("harmonic(100000)", function() return harmonic(100000) end)
row("sieve(100000)", function() return sieve(100000) end)
row("mandel(60, 50)", function() return mandel(60, 50) end)
row("matmul 60x60 (loops)", function() return matmul(A, B) end)
row("nbody(1000)", function() return nbody(1000) end)
row("ode rk45 Lotka-Volterra", lv_rk45)
row("ode bdf Robertson", rob_bdf)
row("record_steps(2000)", function() return record_steps(2000) end)
row("ode rk45, parameter record", lv_params)
row("list_build_sum(10000)", function() return list_build_sum(10000) end)
row("particles(100, 50)", function() return particles(100, 50) end)
println(pad("matmul 60x60 (BLAS *)", 30), lpad(time.format(time.bench(function() return A * B end).best), 10))
