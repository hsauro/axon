# plot.subplot: a grid of cells, each an ordinary figure record.
import plot
import io

plot.figure(width = 800, height = 600, title = "Grid")
plot.subplot(2, 3, 1)
plot.line([1; 2; 3], [1; 4; 9], label = "squares")
plot.title("First")
plot.subplot(2, 3, 6)
plot.bar([2; 5; 3])
plot.title("Sixth")
plot.subplot(2, 3, 2)
plot.scatter([1; 2], [2; 1])

# Going back to a cell keeps what is plotted there.
plot.subplot(2, 3, 1)
plot.xlabel("n")
g = plot.gcf()
println(g.rows, g.cols, g.index, g.title, length(g.cells))
println(length(g.cells[1].series), g.cells[1].title, g.cells[1].xlabel)
println(typeof(g.cells[3]), length(g.cells[6].series), g.cells[6].series[1].type)
# Each cell is sized to its share of the figure, below the overall title.
println(g.cells[1].width, g.cells[6].width)
println(g.cells[1].height == g.cells[6].height, g.cells[1].height < 300)

# Saving draws every cell, and the title above them.
plot.save("_tmp_subplot.svg")
svg = io.read_file("_tmp_subplot.svg")
io.delete_file("_tmp_subplot.svg")
found = {}
for word in {"Grid", "First", "Sixth", "squares"}
  hit = false
  for k in 1:length(svg) - length(word) + 1
    if svg[k] == word[1]
      if svg[k:k + length(word) - 1] == word
        hit = true
        break
      end
    end
  end
  found = append(found, hit)
end
println(found)

# A new figure starts without a grid.
plot.figure()
plot.line([1; 2], [1; 2])
println(typeof(plot.gcf().series), typeof(plot.gcf()) == "record")
