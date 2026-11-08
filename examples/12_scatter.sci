## Scatter plots: two groups of noisy measurements and a least-squares line through each.
## The data are simulated with the random module; the fit uses A \ y.

import random
import plot

random.seed(7)

# Simulated leaf measurements for two plant species: width grows roughly in
# proportion to length, with scatter.
n = 40
len_a = random.uniform(4.0, 10.0, n)
wid_a = 0.45 * len_a + 0.3 + random.normal(0.0, 0.35, n)
len_b = random.uniform(6.0, 14.0, n)
wid_b = 0.25 * len_b + 1.2 + random.normal(0.0, 0.35, n)

# A straight line y = c1 + c2*x through points, by least squares: the
# columns of A are ones and x, and A \ y minimises the squared residuals.
function fit_line(x, y)
  A = [ones(length(x)), x]
  return A \ y
end

# R^2: the fraction of the variation in y that the line explains.
function r_squared(x, y, c)
  r = y - (c[1] + c[2] * x)
  d = y - mean(y)
  return 1 - sum(r .* r) / sum(d .* d)
end

# Three decimals, as text.
function r3(v)
  return string(round(v * 1000) / 1000)
end

function report(name, x, y, c)
  println(name + ": width = " + r3(c[2]) + " * length + " + r3(c[1]) +
    ",  R^2 = " + r3(r_squared(x, y, c)))
end

ca = fit_line(len_a, wid_a)
cb = fit_line(len_b, wid_b)
report("species A", len_a, wid_a, ca)
report("species B", len_b, wid_b, cb)

# The points, each species with its own marker, and the fitted lines.
xa = linspace(4.0, 10.0, 2)
xb = linspace(6.0, 14.0, 2)
plot.figure(title = "Leaf width against length")
plot.scatter(len_a, wid_a, label = "species A", marker = "circle")
plot.scatter(len_b, wid_b, label = "species B", marker = "triangle", size = 7)
plot.line(xa, ca[1] + ca[2] * xa, label = "fit A", color = "#1f77b4", style = "--")
plot.line(xb, cb[1] + cb[2] * xb, label = "fit B", color = "#ff7f0e", style = "--")
plot.xlabel("length (cm)")
plot.ylabel("width (cm)")
plot.show()
