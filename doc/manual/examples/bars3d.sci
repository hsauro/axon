## 3D bars: heights above and below zero.

import plot

g = linspace(0.0, 2 * pi, 7)
Z = zeros(7, 7)
for i in 1:7
  for j in 1:7
    Z[i, j] = sin(g[j]) * cos(g[i])
  end
end

plot.figure(width = 520, height = 400, title = "sin(x) cos(y)")
plot.bar3(g, g, Z, colormap = "coolwarm", width = 0.6, elev = 35, azim = -35)
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")
plot.save("../figures/bars3d.pdf")
