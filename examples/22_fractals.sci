## Fractals drawn on a blank canvas: a Koch snowflake, a Sierpinski triangle,
## a fractal tree and nested circles, each made by a function that calls
## itself. Uses the draw module, whose coordinates have y pointing up.

import draw

# The Koch curve from (x1, y1) to (x2, y2): each segment becomes four, the
# middle third bent out into a peak. The points are added to xs and ys
# (without the end point, which the next segment starts with).
function koch(xs, ys, x1, y1, x2, y2, depth)
  if depth == 0
    return append(xs, x1), append(ys, y1)
  end
  dx = (x2 - x1) / 3
  dy = (y2 - y1) / 3
  ax = x1 + dx
  ay = y1 + dy
  bx = x1 + 2 * dx
  by = y1 + 2 * dy
  # The peak: the middle third turned 60 degrees to the right of the
  # direction of travel, so going round anticlockwise the bumps point out.
  c = cos(pi / 3)
  s = sin(pi / 3)
  px = ax + dx * c + dy * s
  py = ay - dx * s + dy * c
  [xs, ys] = koch(xs, ys, x1, y1, ax, ay, depth - 1)
  [xs, ys] = koch(xs, ys, ax, ay, px, py, depth - 1)
  [xs, ys] = koch(xs, ys, px, py, bx, by, depth - 1)
  [xs, ys] = koch(xs, ys, bx, by, x2, y2, depth - 1)
  return xs, ys
end

# The Sierpinski triangle: a triangle becomes three half-size copies at its
# corners, leaving the middle empty.
function sierpinski(x1, y1, x2, y2, x3, y3, depth)
  if depth == 0
    draw.polygon([x1, x2, x3], [y1, y2, y3], fill = "purple", color = "none")
    return nothing
  end
  sierpinski(x1, y1, (x1 + x2) / 2, (y1 + y2) / 2, (x1 + x3) / 2, (y1 + y3) / 2, depth - 1)
  sierpinski((x1 + x2) / 2, (y1 + y2) / 2, x2, y2, (x2 + x3) / 2, (y2 + y3) / 2, depth - 1)
  sierpinski((x1 + x3) / 2, (y1 + y3) / 2, (x2 + x3) / 2, (y2 + y3) / 2, x3, y3, depth - 1)
end

# A tree: each branch ends in two shorter branches, turned left and right,
# brown and thick at the trunk and green and thin at the tips.
function tree(x, y, angle, len, depth)
  if depth == 0
    return nothing
  end
  x2 = x + len * cos(angle)
  y2 = y + len * sin(angle)
  t = depth / 10
  draw.line(x, y, x2, y2, width = 0.8 * depth, cap = "round",
            color = [0.45 * t, 0.3 + 0.4 * (1 - t), 0.1])
  tree(x2, y2, angle + 0.45, 0.72 * len, depth - 1)
  tree(x2, y2, angle - 0.35, 0.72 * len, depth - 1)
end

# Circles: each holds four smaller circles, around its centre.
function circles(x, y, r, depth)
  draw.circle(x, y, r, color = "blue", fill = [0.3, 0.6, 1.0, 0.15])
  if depth > 0
    for k in 0:3
      a = k * pi / 2
      circles(x + 0.5 * r * cos(a), y + 0.5 * r * sin(a), 0.42 * r, depth - 1)
    end
  end
end

# Four panels side by side, 300 units wide, on a canvas 1200 by 340.
draw.canvas(width = 1200, height = 340, view = [0, 1200, 0, 340])

# Koch snowflake: three Koch curves round a triangle, as one filled polygon.
xs = vector()
ys = vector()
for k in 0:2
  a1 = pi / 2 + 2 * pi * k / 3
  a2 = pi / 2 + 2 * pi * (k + 1) / 3
  [xs, ys] = koch(xs, ys, 150 + 115 * cos(a1), 180 + 115 * sin(a1),
                  150 + 115 * cos(a2), 180 + 115 * sin(a2), 4)
end
draw.polygon(xs, ys, fill = "#cfe8ff", color = "blue")

sierpinski(320, 60, 580, 60, 450, 300, 5)
tree(750, 40, pi / 2, 72, 10)
circles(1050, 180, 120, 4)

draw.text(150, 25, "Koch snowflake", anchor = "middle", size = 14)
draw.text(450, 25, "Sierpinski triangle", anchor = "middle", size = 14)
draw.text(750, 25, "Fractal tree", anchor = "middle", size = 14)
draw.text(1050, 25, "Nested circles", anchor = "middle", size = 14)
println("snowflake points:", length(xs))
draw.show()
