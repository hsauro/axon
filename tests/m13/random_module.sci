import random
# Reference values from an independent implementation of xoshiro256**
# seeded through SplitMix64 (reals from the top 53 bits). Compared within
# 1e-15 rather than with ==, because a 17-digit literal is not always read
# to the nearest double.
function near(x, y)
  return abs(x - y) < 1e-15
end
random.seed(42)
println(near(random.rand(), 0.08386297105988216), near(random.rand(), 0.3789802506626686),
  near(random.rand(), 0.6800434110281394))
random.seed(-5)
println(near(random.rand(), 0.47659061098406563))
# Polar-method normals, two per pair of accepted draws (the last digit of
# log and sqrt may differ between math libraries).
random.seed(1)
z = random.randn(3)
println(abs(z[1] - 1.884396104787977) < 1e-12, abs(z[2] - 0.18978089448693036) < 1e-12,
  abs(z[3] - 1.302090250702661) < 1e-12)
# Integers by rejection: equally likely, both ends included.
random.seed(3)
println(random.randint(1, 6, 8))

# seed makes the prelude's rand repeat too, and resets a kept normal.
random.seed(9)
a = rand(4)
random.randn()
random.seed(9)
println(isequal(rand(4), a))

# Shapes: none for a scalar, n for a vector, m, n for a matrix.
println(typeof(random.rand()), typeof(random.randn()), typeof(random.uniform(0, 1)),
  typeof(random.normal(0, 1)), typeof(random.randint(0, 9)))
println(length(random.rand(5)), length(random.randn(0)), eltype(random.randint(1, 3, 2, 2)))
[m, n] = size(random.normal(0.0, 1.0, 3, 4))
println(m, n)
println(random.rand(2, 0), random.uniform(2.0, 2.0), random.randint(-3, -3, 2))

# Ranges and moments of large samples.
random.seed(7)
u = random.uniform(-1, 3, 100000)
println(min(u) >= -1, max(u) < 3, abs(mean(u) - 1) < 0.02)
x = random.normal(10.0, 2.0, 200, 500)
s = sqrt(mean((x - mean(x)) .* (x - mean(x))))
println(abs(mean(x) - 10) < 0.03, abs(s - 2) < 0.03)
k = random.randint(1, 6, 60000)
println(min(k), max(k), abs(sum(k == 1) - 10000) < 500, abs(sum(k == 6) - 10000) < 500)
println(typeof(random.randint(-9223372036854775807 - 1, 9223372036854775807)))
