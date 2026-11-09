## Using the stats module (stats.sci, in this folder).

import plot
import stats
from stats import linfit, predict

heights = [1.62; 1.75; 1.68; 1.80; 1.71; 1.66; 1.77]
println("mean:", format(stats.mean(heights), 3))
println("variance:", format(stats.variance(heights), 5),
        "population:", format(stats.variance(heights, population = true), 5))
println("std:", format(stats.std(heights), 4))

# A straight line through noisy points.
x = [1.0; 2.0; 3.0; 4.0; 5.0; 6.0; 7.0; 8.0]
y = [2.1; 3.9; 6.2; 7.8; 10.1; 12.2; 13.8; 16.1]
fit = linfit(x, y)
println("slope:", format(fit.slope, 4), "intercept:", format(fit.intercept, 4),
        "r2:", format(fit.r2, 5))

plot.figure(width = 460, height = 320, title = "Least-squares line")
plot.scatter(x, y, label = "data")
plot.line(x, predict(fit, x), label = "fit")
plot.xlabel("x")
plot.ylabel("y")
plot.save("../figures/stats_fit.pdf")
