## Random numbers: seeding, distributions and a Monte Carlo estimate of pi.

import random

random.seed(42)                       # the same numbers on every run
println("dice:", random.randint(1, 6, 8)')
x = random.normal(10.0, 2.0, 10000)
println("mean:", format(mean(x), 3), " sd:", format(sqrt(mean((x - mean(x)) .^ 2)), 3))

# Points in the unit square; the fraction inside the quarter circle is pi/4.
n = 100000
px = rand(n)
py = rand(n)
inside = sum(px .^ 2 + py .^ 2 <= 1.0)
println("pi is about", format(4 * inside / n, 4))
