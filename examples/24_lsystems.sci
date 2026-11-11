## L-systems and the turtle: a few rewriting rules, applied again and again
## to a string, give plants, dragon curves and space-filling curves when a
## turtle draws the result. The last panel is drawn by steering the turtle
## directly.

import draw

# The points of a path scaled to fit the box with lower-left corner (x0, y0),
# width w and height h, keeping its shape and centring it. The NaN values
# that break the path stay NaN.
function fit(xs, ys, x0, y0, w, h)
  ok = xs == xs                       # false at the breaks
  xlo = min(xs[ok])
  xhi = max(xs[ok])
  ylo = min(ys[ok])
  yhi = max(ys[ok])
  s = min(w / max(xhi - xlo, 1e-9), h / max(yhi - ylo, 1e-9))
  cx = x0 + (w - s * (xhi - xlo)) / 2
  cy = y0 + (h - s * (yhi - ylo)) / 2
  return cx + s * (xs - xlo), cy + s * (ys - ylo)
end

# One panel: the L-system's string after n steps, traced and drawn in the
# panel at column col and row row of a 3 x 2 grid, with its title.
function panel(col, row, title, axiom, rules, n, angle, color; heading = 90.0, draw_chars = "FG")
  s = draw.lsystem(axiom, rules, n)
  [xs, ys] = draw.lsystem_path(s, angle, heading = heading, draw = draw_chars)
  x0 = 350 * (col - 1)
  y0 = 350 * (2 - row)
  [xs, ys] = fit(xs, ys, x0 + 25, y0 + 45, 300, 280)
  draw.polyline(xs, ys, color = color, width = 1.0)
  draw.text(x0 + 175, y0 + 22, title + "  (" + string(length(s)) + " symbols)",
            anchor = "middle", size = 13)
end

draw.canvas(width = 1050, height = 700, view = [0, 1050, 0, 700])

# A plant (Lindenmayer): X is a bud that grows into branches; [ and ] start
# and end a branch.
panel(1, 1, "Fractal plant", "X", dict("X" => "F+[[X]-X]-F[-FX]+X", "F" => "FF"), 6, 25,
      "green", heading = 65)
# The dragon curve: paper folded in half again and again.
panel(2, 1, "Dragon curve", "FX", dict("X" => "X+YF+", "Y" => "-FX-Y"), 12, 90, "red")
# The Hilbert curve visits every cell of a grid, never crossing itself.
panel(3, 1, "Hilbert curve", "A", dict("A" => "+BF-AFA-FB+", "B" => "-AF+BFB+FA-"), 5, 90,
      "blue")
# The Sierpinski arrowhead: here A and B both draw.
panel(1, 2, "Sierpinski arrowhead", "A", dict("A" => "B-A-B", "B" => "A+B+A"), 8, 60,
      "purple", heading = 0, draw_chars = "AB")
# Koch's island: the Koch curve on the sides of a square.
panel(2, 2, "Quadratic Koch island", "F+F+F+F", dict("F" => "F+F-F-FF+F+F-F"), 3, 90,
      "orange")

# The turtle steered directly: a square spiral that turns 89 degrees at each
# corner and changes colour as it grows.
draw.turtle(x = 875, y = 175, heading = 0)
for k in 1:150
  draw.pen(color = [0.5 + 0.5 * sin(k / 15), 0.3, 0.5 + 0.5 * cos(k / 15)], width = 1.2)
  draw.forward(k * 0.95)
  draw.left(89)
end
draw.text(875, 22, "Turtle spiral", anchor = "middle", size = 13)

draw.show()
