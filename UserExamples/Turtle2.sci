
import draw

draw.canvas(width = 500, height = 500)
draw.clear()
draw.penup()
draw.goto (250, 250)

draw.pendown()
for i in 1:240
    draw.forward (i)
    draw.left (91.0)
 end;