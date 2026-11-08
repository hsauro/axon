## The Mandelbrot set: real arithmetic in a tight inner loop.
import time

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

print("mandelbrot", mandel(10, 50) > 0, time.format(time.bench(mandel, 60, 50).best))
