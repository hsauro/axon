## A surface plot, saved as PNG and PDF and shown in the plot pane.

import plot

g = linspace(-2.0, 2.0, 40)
Z = zeros(40, 40)
for i in 1:40
  for j in 1:40
    Z[i, j] = exp(-(g[j]^2 + g[i]^2)) * cos(3 * g[j])
  end
end

plot.figure(title = "exp(-r^2) cos(3x)")
plot.surface(g, g, Z)
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")
plot.save("surface.png")
plot.save("surface.pdf")
println("saved surface.png and surface.pdf")
plot.show()
