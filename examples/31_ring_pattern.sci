## A ring of rainbow petals, drawn arc by arc
##
## A port of a Python turtle pattern. Python's tur.circle(radius, extent)
## draws a circular arc in one step; here the turtle's position and heading
## are kept in variables, arc computes the points of each arc and the new
## position and heading, and draw.polyline draws it. A function returns
## several values with return a, b, c, and the caller unpacks them with
## [a, b, c] = f(). The canvas has y pointing up, as turtle's does, and a
## black background.

import draw
import colors

function arc(x, y, heading, radius, extent, steps)
  # Mirrors turtle.circle(radius, extent): positive radius -> center to the
  # left, turtle sweeps counterclockwise; negative radius -> center to the
  # right, clockwise. Returns the path points plus the turtle's new state.
  d = 1.0
  if radius < 0.0
    d = -1.0
  end
  r = abs(radius)
  center_ang = heading + d * 90.0
  cx = x + r * cos(deg2rad(center_ang))
  cy = y + r * sin(deg2rad(center_ang))
  theta0 = atan2(y - cy, x - cx)

  xs = zeros(steps + 1, 1)
  ys = zeros(steps + 1, 1)
  for k in 0:steps
    frac = extent * k / steps
    theta = theta0 + d * deg2rad(frac)
    xs[k + 1] = cx + r * cos(theta)
    ys[k + 1] = cy + r * sin(theta)
  end

  new_heading = heading + d * extent
  return xs, ys, xs[end], ys[end], new_heading
end

draw.canvas(width = 800, height = 800, view = [-400, 400, -400, 400], background = "black")

x = 0.0
y = 0.0
heading = 0.0
steps = 60          # arc resolution (points per 90 degree sweep)

for j in 0:24
  for i in 0:14
    col = colors.hsv2rgb(i / 15.0, j / 25.0, 1.0)

    heading = heading - 90.0
    [xs1, ys1, x, y, heading] = arc(x, y, heading, 200.0 - j * 4.0, 90.0, steps)
    draw.polyline(xs1, ys1, color = col, width = 2)

    heading = heading + 90.0
    [xs2, ys2, x, y, heading] = arc(x, y, heading, 200.0 - j * 4.0, 90.0, steps)
    draw.polyline(xs2, ys2, color = col, width = 2)

    heading = heading - 180.0
    [xs3, ys3, x, y, heading] = arc(x, y, heading, 50.0, 24.0, steps)
    draw.polyline(xs3, ys3, color = col, width = 2)
  end
end

draw.show()
#draw.save("turtle_rings.png")