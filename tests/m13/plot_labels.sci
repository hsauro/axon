# Titles and labels are strings, and nothing removes one.
import plot
plot.figure(title = "Start")
plot.line([1; 2], [1; 2])
plot.title("Waves")
plot.xlabel("t")
plot.ylabel("y")
println(plot.gcf().title, plot.gcf().xlabel, plot.gcf().ylabel)
plot.title(nothing)
plot.ylabel(nothing)
println(typeof(plot.gcf().title), plot.gcf().xlabel, typeof(plot.gcf().ylabel))
plot.figure()
println(typeof(plot.gcf().title))

# Font sizes: kept in the figure, reset by a call without size, checked.
plot.line([1; 2], [1; 2])
plot.title("Big", size = 18)
plot.xlabel("x", size = 14)
f = plot.gcf()
println(f.title_size, f.xlabel_size, typeof(f.ylabel_size))
plot.save("_tmp_labels.png")
plot.xlabel("x")
println(typeof(plot.gcf().xlabel_size))
try
  plot.ylabel("y", size = 0)
catch err
  println(err.kind, err.message)
end
try
  plot.title("t", size = "big")
catch err
  println(err.kind, err.message)
end
import io
println(io.delete_file("_tmp_labels.png"))

# The tick labels' size: kept in the figure (nothing at first), used in 2D
# and 3D pictures, reset with nothing, checked.
plot.figure()
println(typeof(plot.gcf().tick_size))
plot.line([1; 2], [1; 2])
plot.tick_size(7)
println(plot.gcf().tick_size)
plot.save("_tmp_labels.png")
plot.figure()
plot.bar3({"a", "b", "c"}, {"x", "y"}, ones(2, 3))
plot.tick_size(6.5)
plot.save("_tmp_labels.png")
plot.tick_size(nothing)
println(typeof(plot.gcf().tick_size))
try
  plot.tick_size(-1)
catch err
  println(err.kind, err.message)
end
println(io.delete_file("_tmp_labels.png"))
