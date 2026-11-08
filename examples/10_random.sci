## Random numbers: dice, Monte Carlo pi, and a normal histogram against its bell curve.
## Change or remove the seed to get different numbers on each run.

import random
import plot

random.seed(2024)            # the same numbers every run

# Scalars: no shape arguments.
println("rand:   ", random.rand())            # uniform in [0, 1)
println("randn:  ", random.randn())           # standard normal
println("uniform:", random.uniform(5, 10))    # uniform in [5, 10)
println("normal: ", random.normal(100, 15))   # mean 100, sd 15
println("randint:", random.randint(1, 6))     # a die: 1 to 6

# Vectors and matrices: add n, or m, n.
println(random.rand(2, 3))
println(random.randint(1, 6, 2, 5))

# Six thousand dice: each face about a thousand times.
rolls = random.randint(1, 6, 6000)
for face in 1:6
  println("face " + string(face) + ":", sum(rolls == face))
end

# Monte Carlo pi: the fraction of random points in the square [-1, 1]^2 that
# fall inside the unit circle is pi/4.
n = 200000
x = random.uniform(-1, 1, n)
y = random.uniform(-1, 1, n)
inside = sum(x .* x + y .* y <= 1)
println("pi is about", 4 * inside / n)

# A normal sample: its mean and standard deviation, then a histogram.
z = random.normal(0, 1, 20000)
m = mean(z)
s = sqrt(mean((z - m) .* (z - m)))
println("sample mean", round(m * 1000) / 1000, "sd", round(s * 1000) / 1000)

nb = 40
lo = -4.0
w = 8.0 / nb
counts = zeros(nb)
for v in z
  b = floor((v - lo) / w) + 1
  if b >= 1 and b <= nb
    counts[b] = counts[b] + 1
  end
end
centres = linspace(lo + w / 2, -lo - w / 2, nb)
density = counts / (length(z) * w)         # scaled so the area is 1

t = linspace(-4.0, 4.0, 200)
bell = exp(-t .* t / 2) / sqrt(2 * 3.141592653589793)

plot.figure(title = "20000 normal samples")
plot.scatter(centres, density, label = "histogram")
plot.line(t, bell, label = "normal density")
plot.xlabel("z")
plot.ylabel("density")
plot.show()
