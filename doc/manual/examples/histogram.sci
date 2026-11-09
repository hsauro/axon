## A histogram of normal samples against the normal density.

import plot
import random

random.seed(11)
data = random.normal(5.0, 2.0, 2000)

plot.figure(width = 540, height = 320, title = "2000 normal samples")
h = plot.hist_density(data, bins = 30, label = "samples")

# The density of N(5, 2^2) over the same range.
t = linspace(min(data), max(data), 200)
pdf = exp(-(t - 5.0) .^ 2 / (2 * 2.0^2)) / (2.0 * sqrt(2 * pi))
plot.line(t, pdf, label = "density", color = "red", width = 2.0)
plot.xlabel("value")
println("bins:", length(h.counts), " largest count:", max(h.counts))
println("sample mean:", format(mean(data), 3))
plot.save("../figures/histogram.pdf")
