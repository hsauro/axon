## JIT: the same code compiled and interpreted.
## Run this (F9), then click the JIT button in the toolbar and run it again.
## With the JIT on, these functions are compiled to native code at their
## first call; the results are the same, only the time differs.

import time

## Recursion: many small calls.
function fib(n: int): int
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

## A scalar loop.
function harmonic(n: int): real
  s = 0.0
  for k in 1:n
    s = s + 1.0 / k
  end
  return s
end

## Vector reads and writes: the sieve of Eratosthenes.
function count_primes(n: int): int
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

## Real arithmetic in a tight loop: points of the Mandelbrot set.
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
  inside = 0
  for i in 1:n
    for j in 1:n
      if escape(-2.0 + 2.5 * (j - 1) / n, -1.25 + 2.5 * (i - 1) / n, maxit) == maxit
        inside = inside + 1
      end
    end
  end
  return inside
end

## Each result with the time it took.
t = time.clock()
r = fib(24)
println("fib(24)            =", r, "  ", time.format(time.clock() - t))
t = time.clock()
h = harmonic(1000000)
println("harmonic(1000000)  =", h, "  ", time.format(time.clock() - t))
t = time.clock()
p = count_primes(200000)
println("count_primes(2e5)  =", p, "  ", time.format(time.clock() - t))
t = time.clock()
m = mandel(100, 100)
println("mandel(100, 100)   =", m, "  ", time.format(time.clock() - t))
