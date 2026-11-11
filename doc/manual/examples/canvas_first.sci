## A first drawing: a canvas, a line, a circle and a rectangle.
import draw

# A canvas 300 points wide and 200 high. Without a view, x runs from 0 to
# 300 and y from 0 to 200, with y pointing up.
draw.canvas(width = 300, height = 200)

draw.line(20, 20, 280, 180)         # from (20, 20) to (280, 180)
draw.circle(150, 100, 50)           # centre (150, 100), radius 50
draw.rect(30, 120, 80, 50)          # lower-left corner (30, 120), 80 by 50

draw.save("../figures/canvas_first.pdf")
