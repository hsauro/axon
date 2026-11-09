## Scatter plot of noisy data and a least-squares line through it.

import plot
import random

random.seed(3)
x = linspace(0.0, 10.0, 40)
y = 1.5 * x + 2.0 + random.normal(0.0, 1.2, 40)

# Fit y = a + b x: the columns of A are 1 and x; A \ y is least squares.
A = [ones(40), x]
coef = A \ y
println("intercept:", format(coef[1], 3), " slope:", format(coef[2], 3))

plot.figure(width = 520, height = 320, title = "Least-squares fit")
plot.scatter(x, y, label = "data", size = 5.0)
plot.line(x, coef[1] + coef[2] * x, label = "fit", color = "red")
plot.xlabel("x")
plot.ylabel("y")
plot.legend_position("top left")
plot.save("../figures/scatter.pdf")
