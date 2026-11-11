#! error: ArgumentError
# A view must have xmin < xmax and ymin < ymax.
import draw
draw.canvas(view = [1, 0, 0, 1])
