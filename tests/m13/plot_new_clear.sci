# plot.new starts a new plot (as figure); plot.clear empties the current one
# but keeps its frame.
import plot
plot.line([1; 2], [1; 2])
plot.new(title = "Second", width = 500)
plot.line([1; 2], [2; 1])
g = plot.gcf()
println(length(g.series), g.title, g.width, g.height)

plot.xlabel("t")
plot.ylim(0, 10)
plot.legend_position("top left")
plot.bar({"a", "b"}, [3; 4])
plot.clear()
g = plot.gcf()
println(length(g.series), g.title, g.width, g.xlabel, g.ylim[2], g.legend_position)
println(typeof(g.xcategories), g.three_d)

# A cleared figure takes 3D data, or 2D again.
plot.surface([1.0; 2.0], [1.0; 2.0], [1.0, 2.0; 3.0, 4.0])
plot.clear()
plot.line([1; 2], [1; 2])
println(plot.gcf().three_d, length(plot.gcf().series))

# In a grid, clear empties only the current cell.
plot.new()
plot.subplot(1, 2, 1)
plot.line([1; 2], [1; 2])
plot.subplot(1, 2, 2)
plot.bar([1; 2])
plot.clear()
g = plot.gcf()
println(length(g.cells[1].series), length(g.cells[2].series))
plot.new()
