
import draw

draw.canvas(width = 800, height = 800, view = [-700, 700, -700, 700], background = "black")
draw.turtle(x = 0.0, y = 0.0)
draw.pen(width = 4)

REPEATS = 7
points = {}

function hsv2rgb(h, s, v)
  # h, s, v in [0,1] -> [r,g,b] in [0,1], same algorithm as Python's colorsys
  if s == 0.0
    return [v, v, v]
  end
  i = floor(h * 6.0)
  f = h * 6.0 - i
  p = v * (1.0 - s)
  q = v * (1.0 - s * f)
  t = v * (1.0 - s * (1.0 - f))
  k = mod(int(i), 6)
  if k == 0
    return [v, t, p]
  elseif k == 1
    return [q, v, p]
  elseif k == 2
    return [p, v, t]
  elseif k == 3
    return [p, q, v]
  elseif k == 4
    return [t, p, v]
  else
    return [v, p, q]
  end
end

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
    draw.pen(color = hsv2rgb((i - 1 + offset) / 700, 1.0, 1.0))
    draw.penup()
    draw.goto(points[i][1], points[i][2])
    draw.pendown()
    draw.goto(points[j][1], points[j][2])
  end
end

draw.show()
