## Four views: a line plot, bars, a histogram and a 3D surface in one figure.
## plot.subplot(rows, cols, k) picks the cell that later plotting calls go to;
## in the IDE each cell can be zoomed, panned (or rotated) and edited, and the
## Copy and Save buttons above the plot take the whole grid.

import plot
import random

random.seed(7)

# The data for the four cells.
t = linspace(0.0, 2 * pi, 200)
counts = [12; 7; 9; 15]
data = random.randn(1000)

xs = linspace(-2.0, 2.0, 25)
ys = linspace(-2.0, 2.0, 25)
Z = zeros(25, 25)
for i in 1:25
  for j in 1:25
    Z[i, j] = exp(-(xs[j]^2 + ys[i]^2))
  end
end

# A 2 by 2 grid; the figure's title goes above it. Cells are numbered along
# each row: 1 and 2 on top, 3 and 4 below.
plot.figure(width = 900, height = 640, title = "Four views")

plot.subplot(2, 2, 1)
plot.line(t, sin(t), label = "sin")
plot.line(t, cos(t), label = "cos", style = "--")
plot.title("Waves")
plot.xlabel("t")

plot.subplot(2, 2, 2)
plot.bar({"A", "C", "G", "T"}, counts)
plot.title("Bases")

plot.subplot(2, 2, 3)
plot.hist(data, bins = 20)
plot.title("Normal sample")

plot.subplot(2, 2, 4)
plot.surface(xs, ys, Z)
plot.title("Gaussian")

# No plot.show() needed: the figure is shown when the program ends. To keep
# it as a file instead, add for example plot.save("four_views.pdf").
