
import draw

awidth = 300; aheight = 300
draw.canvas(width = awidth, height = aheight)
draw.rect(0, 0, awidth, aheight, fill = "white", color = "none")

x = awidth/2
y = aheight/2
r = 50
w = 5

draw.circle(x, y, r,          fill = "red",     color = "none")
draw.circle(x, y, r - w,      fill = "orange",  color = "none")
draw.circle(x, y, r - w*2,    fill = "yellow",  color = "none")
draw.circle(x, y, r - w*3,    fill = "green",   color = "none")
draw.circle(x, y, r - w*4,    fill = "blue",    color = "none")
draw.circle(x, y, r - w*5,    fill = "#00008b", color = "none")  # darkblue
draw.circle(x, y, r - w*6,    fill = "#4b0082", color = "none")  # darkpurple
draw.circle(x, y, r - w*7,    fill = "white",   color = "none")

draw.show()
