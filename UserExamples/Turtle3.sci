
import draw

draw.pendown()
draw.clear()

function square (size)
   draw.forward (size)
   draw.right (90)
   draw.forward (size)
   draw.right (90)
   draw.forward (size)
   draw.right (90)
   draw.forward (size) 
end

for i in 1:18
    square (120)
    draw.left (5)
end