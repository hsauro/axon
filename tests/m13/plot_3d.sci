# 3D curves and markers: line3, scatter3 and view, alone and with a surface.
import plot
import io

t = linspace(0.0, 6.0, 30)
plot.figure(title = "Helix")
plot.line3(cos(t), sin(t), t, label = "helix", width = 2)
plot.scatter3([1.0; -1.0], [0.0; 0.0], [0.0; 3.0], label = "ends", marker = "diamond", size = 8)
plot.view(-30, 20)
f = plot.gcf()
println(f.three_d, f.azim, f.elev, length(f.series))
s = f.series[1]
println(s.type, length(s.z), s.width, s.color)
println(f.series[2].type, f.series[2].marker, f.series[2].size, f.series[2].color)

# A NaN leaves a gap; the picture still renders, in every format.
plot.line3([0.0; 1.0; 0.0 / 0.0; 2.0; 3.0], [0.0; 1.0; 2.0; 3.0; 4.0], [1.0; 2.0; 3.0; 4.0; 5.0])
for p in {"_tmp_3d.svg", "_tmp_3d.png"}
  plot.save(p)
  println(io.delete_file(p))
end

# A curve on a surface.
g = linspace(-1.0, 1.0, 6)
Z = zeros(6, 6)
for i in 1:6
  for j in 1:6
    Z[i, j] = g[i] * g[j]
  end
end
plot.figure()
plot.surface(g, g, Z, label = "saddle")
plot.line3(g, g, g .* g, color = "red")
println(length(plot.gcf().series))
plot.save("_tmp_3d.svg")
println(io.delete_file("_tmp_3d.svg"))
