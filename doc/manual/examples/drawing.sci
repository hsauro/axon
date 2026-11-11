## Drawing on a blank canvas: a recursive tree, an L-system plant drawn by
## the turtle, and a Julia set as an image.

import draw

# A tree: each branch ends in two shorter ones.
function tree(x, y, angle, len, depth)
  if depth == 0
    return nothing
  end
  x2 = x + len * cos(angle)
  y2 = y + len * sin(angle)
  draw.line(x, y, x2, y2, width = 0.6 * depth, cap = "round",
            color = [0.4 * depth / 9, 0.6 - 0.3 * depth / 9, 0.1])
  tree(x2, y2, angle + 0.5, 0.7 * len, depth - 1)
  tree(x2, y2, angle - 0.4, 0.7 * len, depth - 1)
end

# How fast z -> z^2 + c runs away from z0 = x + y i (a Julia set), as a
# smooth count; NaN if it stays.
function julia(x: real, y: real, cr: real, ci: real): real
  for k in 1:200
    if x * x + y * y > 256.0
      return k - log(0.5 * log(x * x + y * y)) / log(2.0)
    end
    t = x * x - y * y + cr
    y = 2.0 * x * y + ci
    x = t
  end
  return 0.0 / 0.0
end

function julia_image(n: int): matrix{real}
  J = zeros(n, n)
  for i in 1:n
    y = 1.6 - 3.2 * (i - 1) / (n - 1)
    for j in 1:n
      x = -1.6 + 3.2 * (j - 1) / (n - 1)
      J[i, j] = julia(x, y, -0.8, 0.156)
    end
  end
  return J
end

draw.canvas(width = 600, height = 220, view = [0, 600, 0, 220])

# Left: the recursive tree.
tree(100, 20, pi / 2, 50, 9)

# Middle: a plant from an L-system, drawn by the turtle.
plant = draw.lsystem("X", dict("X" => "F+[[X]-X]-F[-FX]+X", "F" => "FF"), 5)
draw.turtle(x = 270, y = 15, heading = 70)
draw.pen(color = "green", width = 0.8)
draw.lsystem_draw(plant, 1.9, 25)

# Right: a Julia set, 300 x 300 pixels in a 190-point square.
J = sqrt(julia_image(300))
draw.image(J, x = 400, y = 15, w = 190, h = 190, colormap = "hsv",
           nan_color = "black")

println(length(plant), "symbols in the plant")
draw.save("../figures/drawing.pdf")
