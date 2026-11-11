## The Mandelbrot set, drawn as an image: every pixel is a point c of the
## complex plane, coloured by how fast z -> z^2 + c runs away from 0. The
## loops run as compiled code, so a picture of half a million pixels takes
## a moment.

import draw
import time

# The escape count of c = cr + ci i: the number of steps before |z| > 16,
# made continuous (the "smooth" count) so the colours blend; NaN for points
# that have not escaped after maxit steps, taken to be in the set.
function escape(cr: real, ci: real, maxit: int): real
  zr = 0.0
  zi = 0.0
  for k in 1:maxit
    zr2 = zr * zr
    zi2 = zi * zi
    if zr2 + zi2 > 256.0
      return k + 1 - log(0.5 * log(zr2 + zi2)) / log(2.0)
    end
    zi = 2.0 * zr * zi + ci
    zr = zr2 - zi2 + cr
  end
  return 0.0 / 0.0
end

# The escape counts over the rectangle [x0, x1] x [y0, y1] of the plane, as
# an ny x nx matrix with row 1 at the top.
function mandelbrot(nx: int, ny: int, x0: real, x1: real, y0: real, y1: real,
                    maxit: int): matrix{real}
  M = zeros(ny, nx)
  for i in 1:ny
    ci = y1 - (i - 1) * (y1 - y0) / (ny - 1)
    for j in 1:nx
      cr = x0 + (j - 1) * (x1 - x0) / (nx - 1)
      M[i, j] = escape(cr, ci, maxit)
    end
  end
  return M
end

# Deep blue through white and gold to brown, and back to blue: a palette
# that repeats well.
palette = [0.0,  0.03, 0.15;
           0.1,  0.35, 0.7;
           0.95, 0.95, 1.0;
           1.0,  0.75, 0.1;
           0.5,  0.15, 0.0;
           0.0,  0.03, 0.15]

# The whole set, and a small window in "seahorse valley", the cleft between
# the main body and the round bulb to its left.
x0 = -2.2
x1 = 0.8
y0 = -1.2
y1 = 1.2
zx0 = -0.7550
zx1 = -0.7390
zy0 = 0.0950
zy1 = 0.1078

t0 = time.clock()
whole = mandelbrot(600, 480, x0, x1, y0, y1, 200)
zoom = mandelbrot(600, 480, zx0, zx1, zy0, zy1, 800)
println("1.15 million escape counts in", format(time.clock() - t0, 2), "seconds")

# Two panels side by side; the counts are spread out by a square root so
# the colours change quickly near the set, and points in the set are black.
draw.canvas(width = 1200, height = 520, view = [0, 1200, 0, 520], background = "black")
draw.image(sqrt(whole), x = 0, y = 40, w = 600, h = 480, colormap = palette,
           nan_color = "black")
draw.image(sqrt(zoom), x = 600, y = 40, w = 600, h = 480, colormap = palette,
           nan_color = "black")
# A circle round the zoomed window, in the left panel's coordinates.
cx = 600 * ((zx0 + zx1) / 2 - x0) / (x1 - x0)
cy = 40 + 480 * ((zy0 + zy1) / 2 - y0) / (y1 - y0)
draw.circle(cx, cy, 9, color = "white", width = 1.5)
draw.text(300, 20, "The Mandelbrot set", anchor = "middle", color = "white", size = 14)
draw.text(900, 20, "Seahorse valley, magnified " + format((x1 - x0) / (zx1 - zx0), 0) + " times",
          anchor = "middle", color = "white", size = 14)
draw.show()
