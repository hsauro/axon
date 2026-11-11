
import draw

function draw_rainbow(x, y, r, width)
  colors = {"red", "orange", "yellow", "green", "blue", "#00008b", "#4b0082", "white"}
  for k in 0:7
    rk = r - width * k
    if rk > 0
      draw.circle(x, y, rk, fill = colors[k + 1], color = "none")
    end
  end
end

draw.canvas(width = 300, height = 300)
draw.rect(0, 0, 300, 300, fill = "white", color = "none")

for i in 1:100
  x = floor(rand() * 300)
  y = floor(rand() * 300)
  r = floor(rand() * 30) + 10
  width = floor(rand() * 5) + 2
  println("Drawing Circle With " + string(x) + " " + string(y) + " " + string(r) + " " + string(width))
  draw_rainbow(x, y, r, width)
end

draw.show()
