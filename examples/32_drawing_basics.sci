## The drawing calls, one panel each
##
## A tour of the draw module: each of the nine panels shows one kind of call,
## with its name underneath, so you can see what the calls look like and
## what they draw. The canvas is 660 by 660 points and shows the square
## [0, 3] x [0, 3] of the plane, so each panel is one unit wide, with y
## pointing up. Everything after the semicolon in a call is a keyword, given
## by name: color, width, fill, dash and so on. A colour is one of the
## names graphics knows ("red", "blue", "orange", ...), a vector [r, g, b]
## of parts from 0 to 1 (a fourth part makes it see-through), or one of the
## 140 web colour names through the colors module: colors.rgb("Gold").

import draw
import colors

draw.canvas(width = 660, height = 660, view = [0, 3, 0, 3])

# Thin grey lines between the panels. draw.style sets the colour and width of
# every shape drawn after it that does not give its own; draw.style() resets.
draw.style(color = [0.8, 0.8, 0.8], width = 0.5)
for k in 1:2
  draw.line(k, 0, k, 3)
  draw.line(0, k, 3, k)
end
draw.style()

# A panel's caption: the call's name, centred near the bottom of the panel.
function caption(x0, y0, s)
  draw.text(x0 + 0.5, y0 + 0.1, s, size = 12, anchor = "middle", font = "monospace")
end

# Top row ---------------------------------------------------------------

# line: a straight line between two points.
x0 = 0
y0 = 2
draw.line(x0 + 0.1, y0 + 0.85, x0 + 0.9, y0 + 0.85)
draw.line(x0 + 0.1, y0 + 0.7, x0 + 0.9, y0 + 0.7, color = "red", width = 3)
draw.line(x0 + 0.1, y0 + 0.55, x0 + 0.9, y0 + 0.55, color = "blue", width = 8, cap = "round")
draw.line(x0 + 0.1, y0 + 0.4, x0 + 0.9, y0 + 0.4, color = "green", width = 2, dash = [8, 4])
caption(x0, y0, "line")

# polyline: a line through many points, here a sine wave.
x0 = 1
xs = linspace(0.1, 0.9, 60)
ys = 0.55 + 0.25 * sin(2 * pi * (xs - 0.1) / 0.8 * 1.5)
draw.polyline(x0 + xs, y0 + ys, color = "purple", width = 2)
caption(x0, y0, "polyline")

# polygon: a closed shape through the points, filled and outlined.
x0 = 2
draw.polygon(x0 + [0.1, 0.45, 0.1], y0 + [0.3, 0.55, 0.85], fill = "orange")
angles = linspace(90, 90 + 720, 6)               # a five-pointed star
draw.polygon(x0 + 0.68 + 0.22 * cos(deg2rad(angles)), y0 + 0.57 + 0.22 * sin(deg2rad(angles)),
             fill = colors.rgb("Gold"), color = "brown", width = 1.5)
caption(x0, y0, "polygon")

# Middle row ------------------------------------------------------------

# rect: lower-left corner, width and height.
x0 = 0
y0 = 1
draw.rect(x0 + 0.1, y0 + 0.3, 0.45, 0.5, fill = colors.rgb("SkyBlue"), color = colors.rgb("Navy"),
          width = 2)
draw.rect(x0 + 0.6, y0 + 0.45, 0.3, 0.3, color = "red")
caption(x0, y0, "rect")

# circle and ellipse: centre and radius (radii); colours with a fourth part
# are see-through.
x0 = 1
draw.circle(x0 + 0.35, y0 + 0.55, 0.22, fill = "yellow")
draw.ellipse(x0 + 0.62, y0 + 0.55, 0.3, 0.13, angle = 30, fill = [0.2, 0.5, 1.0, 0.5],
             color = "none")
caption(x0, y0, "circle, ellipse")

# arc: centre, radius, start angle and sweep in degrees, anticlockwise; with
# wedge = true it is a filled slice, as in a pie chart.
x0 = 2
draw.arc(x0 + 0.27, y0 + 0.55, 0.2, 0, 270, color = colors.rgb("Teal"), width = 3)
draw.arc(x0 + 0.73, y0 + 0.55, 0.2, 30, 300, wedge = true, fill = colors.rgb("Tomato"))
caption(x0, y0, "arc")

# Bottom row ------------------------------------------------------------

# points: markers at the points, in six shapes.
x0 = 0
y0 = 0
shapes = {"circle", "square", "diamond", "triangle", "plus", "cross"}
for k in 1:6
  draw.points(x0 + 0.15 + 0.14 * (k - 1), y0 + 0.65, shape = shapes[k], size = 12,
              color = "green")
end
draw.points(x0 + linspace(0.15, 0.85, 8), y0 + 0.35 + 0.1 * sin(linspace(0, 6, 8)),
            size = 6, color = "red")
caption(x0, y0, "points")

# text: anchor says which end of the text sits on the point (a red dot).
x0 = 1
for k in 1:3
  a = {"start", "middle", "end"}[k]
  draw.points(x0 + 0.5, y0 + 0.85 - 0.15 * k, size = 4, color = "red")
  draw.text(x0 + 0.5, y0 + 0.85 - 0.15 * k, a, size = 12, anchor = a)
end
draw.text(x0 + 0.2, y0 + 0.3, "turned", size = 11, angle = 30, color = "blue")
draw.text(x0 + 0.85, y0 + 0.3, "bold", size = 14, bold = true, anchor = "end")
caption(x0, y0, "text")

# style and the turtle: draw.style colours the shapes without their own
# colour; the turtle has its own pen and draws as it moves.
x0 = 2
draw.style(color = colors.rgb("Navy"), width = 2)
draw.circle(x0 + 0.2, y0 + 0.75, 0.1)
draw.rect(x0 + 0.1, y0 + 0.3, 0.2, 0.2)
draw.style()
draw.turtle(x = x0 + 0.65, y = y0 + 0.55, heading = 0)
draw.pen(color = colors.rgb("Crimson"), width = 1.5)
step = 0.01
for k in 1:36
  draw.forward(step)
  draw.left(50)
  step = step + 0.008
end
caption(x0, y0, "style, turtle")

draw.show()
