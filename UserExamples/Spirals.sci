
import draw

draw.canvas(width = 800, height = 800, view = [-700, 700, -700, 700], background = "black")
draw.turtle(x = 0.0, y = 0.0)
draw.pen(width = 4)
h = 0

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


# units to the turtle's left, drawn as short straight steps.
function circle(radius, extent)
  n = 1 + int(min(11 + abs(radius) / 6, 59) * abs(extent) / 360)
  w = extent / n
  l = 2 * radius * sin(deg2rad(w / 2))
  if radius < 0
    l = -l
    w = -w
  end
  draw.left(w / 2)
  for k in 1:n
    draw.forward(l)
    draw.left(w)
  end
  draw.right(w / 2)
end

function mydraw(ang, n)
  circle(5 + n, 69)
  draw.left(ang)
  circle(5 + 2 * n, 60)
end

for i in 1:200
  draw.pen(color = hsv2rgb(h, 1.0, 1.0))
  h = h + 0.005
  draw.penup()
  mydraw(90, i)
  mydraw(180, i)
  draw.pendown()
  mydraw(1 / 2, 0)
  mydraw(180, i / 2)
  mydraw(120, 0)
end

draw.show()
