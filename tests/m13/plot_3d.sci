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

# Colour maps, and colouring by another matrix than the heights.
plot.figure()
plot.surface(g, g, Z, colormap = "plasma", color_by = abs(Z))
s = plot.gcf().series[1]
println(s.colormap, size(s.c, 1), size(s.c, 2), s.c[1, 1])
plot.save("_tmp_3d.png")
println(io.delete_file("_tmp_3d.png"))
plot.figure()
plot.surface(g, g, Z, colormap = "coolwarm")
println(typeof(plot.gcf().series[1].c))
try
  plot.surface(g, g, Z, colormap = "rainbow")
catch err
  println(err.kind)
end
try
  plot.surface(g, g, Z, color_by = zeros(2, 2))
catch err
  println(err.kind, err.message)
end

# 3D bars: Z alone, with x and y, a vector, one colour, and the errors.
B = [1.0, -2.0, 3.0; 0.5, 0.0, -1.0]
plot.figure()
plot.bar3(B, label = "bars")
s = plot.gcf().series[1]
println(s.type, s.x[3], s.y[2], s.width, s.colormap, typeof(s.color), typeof(s.c))
plot.save("_tmp_3d.png")
println(io.delete_file("_tmp_3d.png"))
plot.figure()
plot.bar3([10.0; 20.0; 30.0], [0.0; 5.0], B, width = 0.5, color = "orange", edges = false,
          elev = 20, azim = 30)
f = plot.gcf()
s = f.series[1]
println(s.x[2], s.y[2], s.width, s.color, s.edges, f.elev, f.azim)
plot.save("_tmp_3d.svg")
println(io.delete_file("_tmp_3d.svg"))
plot.figure()
plot.bar3([1.0; 2.0; 4.0], color_by = [3.0; 2.0; 1.0], colormap = "jet")
s = plot.gcf().series[1]
println(size(s.z, 1), size(s.z, 2), s.c[3, 1])
try
  plot.bar3([1.0, 2.0], B)
catch err
  println(err.kind, err.message)
end
try
  plot.bar3([1.0; 2.0], [1.0; 2.0], B)
catch err
  println(err.kind, err.message)
end
try
  plot.bar3(B, width = 1.5)
catch err
  println(err.kind, err.message)
end
try
  plot.bar3(B, colormap = "rainbow")
catch err
  println(err.kind)
end
try
  plot.bar3("tall")
catch err
  println(err.kind, err.message)
end
plot.figure()
plot.line([1.0; 2.0], [1.0; 2.0])
try
  plot.bar3(B)
catch err
  println(err.kind, err.message)
end
