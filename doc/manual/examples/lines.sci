## Line plots: styles, markers, labels and a legend.

import plot

x = linspace(0.0, 2 * pi, 200)
plot.figure(width = 560, height = 320, title = "Line styles")
plot.line(x, sin(x), label = "sin x")
plot.line(x, cos(x), label = "cos x", style = "--")
plot.line(x, sin(2 * x) / 2, label = "sin 2x / 2", style = ":", width = 2.5)

# Markers at a few points only: a second, coarser series.
xm = linspace(0.0, 2 * pi, 9)
plot.line(xm, -sin(xm), label = "-sin x", style = "-.", marker = "square")

plot.xlabel("x")
plot.ylabel("y")
plot.xlim(0.0, 2 * pi)
plot.legend_position("outside")
plot.save("../figures/lines.pdf")
