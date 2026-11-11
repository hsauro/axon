## Choosing the view: the canvas shows x and y from -1.2 to 1.2.
import draw

draw.canvas(width = 240, height = 240, view = [-1.2, 1.2, -1.2, 1.2])

draw.line(-1.2, 0, 1.2, 0, color = "gray")        # the x axis
draw.line(0, -1.2, 0, 1.2, color = "gray")        # the y axis
draw.circle(0, 0, 1, color = "blue", width = 2)    # the unit circle

x = linspace(-1, 1, 100)
draw.polyline(x, x .^ 3, color = "red", width = 2) # y = x^3

draw.points(0.6, 0.8, size = 6)                    # a point on the circle
draw.text(0.55, 0.9, "(0.6, 0.8)", size = 10, anchor = "end")

draw.save("../figures/canvas_view.pdf")
