# draw.style: the colour and width shapes use when their own are not given,
# and the canvas keeping call order when turtle moves and shapes are mixed.
import draw

# The colour and width of every item on the canvas, one line each.
function report()
  for it in draw.scene().items
    w = "-"                                    # markers and text have no width
    if it.kind != "markers" and it.kind != "text"
      w = string(it.width)
    end
    println(it.kind, it.color, w)
  end
end

draw.canvas(width = 100, height = 100, view = [0, 1, 0, 1])
draw.line(0, 0, 1, 1)                          # defaults: black, 1
draw.style(color = "red", width = 3)
draw.line(0, 0, 1, 1)                          # the style: red, 3
draw.circle(0.5, 0.5, 0.2, fill = "yellow")    # outline red, 3
draw.rect(0, 0, 0.5, 0.5, color = "blue")      # own colour, the style's width
draw.points([0.5], [0.5])                      # red, no width
draw.text(0.5, 0.5, "label")                   # text keeps black
draw.style(width = 0.5)                        # only the width changes
draw.polyline([0.0, 1.0], [0.0, 1.0])          # red, 0.5
draw.style()                                   # back to black, 1
draw.polygon([0.0, 1.0, 1.0], [0.0, 0.0, 1.0])
report()

# The turtle's line comes before a shape drawn after it, so the shape covers it.
draw.canvas(width = 100, height = 100, view = [-1, 1, -1, 1])
draw.turtle(x = -0.8, y = 0.0, heading = 0.0)
draw.forward(1.6)
draw.circle(0, 0, 0.5, fill = "yellow")
draw.forward(0.1)
report()
