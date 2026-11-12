## Conway's Game of Life, animated
##
## A grid of cells, each alive or dead. Every generation, a live cell with
## two or three live neighbours survives, a dead cell with exactly three
## comes alive, and every other cell dies or stays dead. The grid wraps
## round at its edges. Each generation is computed by a compiled function
## and shown as one frame of an animation in the plot pane.

import draw
import random
import time

rows = 100
cols = 150
cell = 5                  # points per cell on the canvas
generations = 300

# The next generation of G (1.0 alive, 0.0 dead).
function step(G: matrix{real}): matrix{real}
  m = size(G, 1)
  n = size(G, 2)
  N = zeros(m, n)
  for j in 1:n
    left = j - 1
    if left < 1
      left = n
    end
    right = j + 1
    if right > n
      right = 1
    end
    for i in 1:m
      up = i - 1
      if up < 1
        up = m
      end
      down = i + 1
      if down > m
        down = 1
      end
      s = G[up, left] + G[up, j] + G[up, right] + G[i, left] + G[i, right] +
          G[down, left] + G[down, j] + G[down, right]
      if s == 3.0 or (s == 2.0 and G[i, j] == 1.0)
        N[i, j] = 1.0
      end
    end
  end
  return N
end

# A random start: about a quarter of the cells alive. The comparison gives a
# matrix of bools; adding 0.0 turns it into reals, which step compiles for.
random.seed(2026)
G = (random.rand(rows, cols) < 0.25) + 0.0

# Dead cells pale, live ones dark blue.
palette = [0.96, 0.96, 0.93; 0.10, 0.25, 0.55]

t0 = time.clock()
for gen in 1:generations
  draw.canvas(width = cols * cell, height = rows * cell, view = [0, cols, 0, rows])
  draw.image(G, colormap = palette, vmin = 0, vmax = 1)
  draw.text(1, rows - 2, "generation " + string(gen) + ", " + string(int(sum(G))) + " alive",
            size = 12, color = "black")
  draw.frame(fps = 10)
  G = step(G)
end
println("Ran " + string(generations) + " generations in " + time.format(time.clock() - t0))
