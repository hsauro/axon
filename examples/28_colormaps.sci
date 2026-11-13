## Colour maps: the Rosenbrock function six ways
##
## The Rosenbrock function f(x, y) = (1 - x)^2 + 100 (y - x^2)^2 has its
## minimum, 0, at (1, 1), at the bottom of a long curved valley; away from
## it the values climb into the thousands. Coloured by height, almost the
## whole surface falls in the bottom of the colour range (the last panel).
## Colouring by log10(1 + f) instead, with color_by, keeps the true heights
## but spreads the colours over the whole surface, and the valley shows. The
## first five panels do that with each of the colour maps surfaces have.

import plot

# The grid: rows go with y and columns with x, so Z[i, j] = f(x[j], y[i]).
x = linspace(-2.0, 2.0, 81)
y = linspace(-1.0, 3.0, 81)
Z = zeros(length(y), length(x))
for i in 1:length(y)
  for j in 1:length(x)
    Z[i, j] = (1 - x[j])^2 + 100 * (y[i] - x[j]^2)^2
  end
end
logZ = log10(1 + Z)

plot.figure(width = 1200, height = 820, title = "The Rosenbrock function and the colour maps")

maps = {"viridis", "plasma", "coolwarm", "gray", "jet"}
for k in 1:length(maps)
  plot.subplot(2, 3, k)
  plot.surface(x, y, Z, color_by = logZ, colormap = maps[k], edges = false)
  plot.title(maps[k] + ", coloured by log10(1 + f)", size = 12)
  plot.xlabel("x")
  plot.ylabel("y")
  plot.zlabel("f")
end

# For comparison: the same surface coloured by its height.
plot.subplot(2, 3, 6)
plot.surface(x, y, Z, edges = false)
plot.title("viridis, coloured by height", size = 12)
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("f")

plot.show()
