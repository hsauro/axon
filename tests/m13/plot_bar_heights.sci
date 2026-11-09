# plot.bar(y): bars at 1, 2, ..., the same as plot.bar(1:n, y).
import plot

plot.bar([3.0; 1.0; 2.0])
s = plot.gcf().series[1]
println(s.left[1], s.right[1], s.left[3], s.right[3])
println(s.heights[2])

plot.figure()
plot.bar([3.0; 1.0; 2.0], width = 0.5, label = "h")
s = plot.gcf().series[1]
println(s.left[2], s.right[2], s.label)
plot.save("_tmp_bar_heights.png")
import io
println(io.delete_file("_tmp_bar_heights.png"))
