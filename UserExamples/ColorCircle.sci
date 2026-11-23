
import draw
import colors

draw.canvas(width = 800, height = 800, view = [-700, 700, -700, 700], background = "black")
draw.turtle(x = 0.0, y = 0.0)
draw.pen(width = 4)

REPEATS = 7
points = {}

for i in 1:700
    angle = (i / 700) * 2 * pi
    x = 250 * cos(angle)
    y = 250 * sin(angle)
    points = append(points, {x, y})
end

for r in 1:REPEATS
  offset = (r - 1) * div(700, REPEATS)
  for i in 1:700
    j = mod(2 * (i - 1), 700) + 1
    draw.pen(color = colors.hsv2rgb((i - 1 + offset) / 700, 1.0, 1.0))
    draw.penup()
    draw.goto(points[i][1], points[i][2])
    draw.pendown()
    draw.goto(points[j][1], points[j][2])
  end
end

draw.show()
