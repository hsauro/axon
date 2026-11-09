## A surface: z = sin(r) / r over a grid.

import plot

xs = linspace(-8.0, 8.0, 41)
ys = linspace(-8.0, 8.0, 41)
Z = zeros(41, 41)
for i in 1:41
  for j in 1:41
    r = sqrt(xs[j]^2 + ys[i]^2) + 1e-9
    Z[i, j] = sin(r) / r
  end
end

plot.figure(width = 520, height = 400, title = "sin(r) / r")
plot.surface(xs, ys, Z, elev = 35, azim = -50)
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")
plot.save("../figures/surface.pdf")
