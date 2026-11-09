## 3D scatter plots: three clusters of points in space, each in its own colour.
## Each cluster is a matrix with one row per point (x, y, z); its columns give
## scatter3 its coordinates. In the IDE, drag to rotate and use the wheel to zoom.

import plot
import random

random.seed(4)

# n points scattered around a centre, as an n by 3 matrix: one row per point.
function cluster(n, centre, spread)
  P = random.normal(0.0, spread, n, 3)
  for k in 1:3
    P[:, k] = P[:, k] + centre[k]
  end
  return P
end

centres = [0.0, 0.0, 0.0; 4.0, 1.0, 2.0; 1.0, 4.0, 4.0]
clusters = {cluster(300, centres[1, :], 0.6), cluster(200, centres[2, :], 0.8),
            cluster(150, centres[3, :], 0.5)}
names = {"A", "B", "C"}
colours = {"#1f77b4", "#ff7f0e", "#2ca02c"}

plot.new(title = "Three clusters", width = 640, height = 520)
for k in 1:3
  P = clusters[k]
  plot.scatter3(P[:, 1], P[:, 2], P[:, 3], size = 3, color = colours[k],
                label = names[k] + " (" + string(size(P, 1)) + " points)")
end

# The centre of each cluster, found from its points, as a larger marker.
found = zeros(3, 3)
for k in 1:3
  found[k, :] = mean(clusters[k], 1)
end
plot.scatter3(found[:, 1], found[:, 2], found[:, 3], size = 10, color = "black",
              marker = "diamond", label = "centres")

plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")
plot.view(-40, 25)

# How far each found centre is from the one the points were drawn around.
for k in 1:3
  d = sqrt(sum((found[k, :] - centres[k, :]) .^ 2))
  println(names[k], "centre off by", format(d, 3))
end
