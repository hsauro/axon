## 3D bar charts: a 2-D histogram, and heights above and below zero
##
## On the left, 5000 points from two correlated normal variables are counted
## in a 12 by 12 grid of bins, and each count is drawn as a bar standing on
## its bin: the bars rise into a ridge along the diagonal, the shape of the
## correlation. On the right, sin(x) cos(y) on a coarse grid gives bars
## that go up and down, coloured with the diverging map coolwarm. In the IDE,
## drag a chart to turn it and look from any side, even from below.

import plot
import random

# Correlated normal pairs: y = 0.6 x + 0.8 v has correlation 0.6 with x.
random.seed(7)
n = 5000
x = random.randn(n)
y = 0.6 * x + 0.8 * random.randn(n)

# Count the points in bins 0.5 wide from -3 to 3 (points outside are left
# out). Rows go with y and columns with x, so counts[i, j] is above
# (centres[j], centres[i]).
bins = 12
centres = linspace(-2.75, 2.75, bins)
counts = zeros(bins, bins)
for k in 1:n
  j = floor((x[k] + 3) / 0.5) + 1
  i = floor((y[k] + 3) / 0.5) + 1
  if i >= 1 and i <= bins and j >= 1 and j <= bins
    counts[i, j] = counts[i, j] + 1
  end
end

plot.figure(width = 1100, height = 520, title = "3D bar charts")

plot.subplot(1, 2, 1)
plot.bar3(centres, centres, counts)
plot.title("A 2-D histogram of correlated normals")
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("count")

# Heights of both signs: the bars start at 0 and go down for negative values.
g = linspace(0.0, 2 * pi, 9)
Z = zeros(9, 9)
for i in 1:9
  for j in 1:9
    Z[i, j] = sin(g[j]) * cos(g[i])
  end
end
plot.subplot(1, 2, 2)
plot.bar3(g, g, Z, colormap = "coolwarm", width = 0.6, azim = -35, elev = 35)
plot.title("sin(x) cos(y)")
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")

plot.show()
