# Spaces between a function and its argument list, or between a value and
# its index brackets, change nothing, in any context: elements of literals
# are separated by commas, so f (x) can only be a call (reference, "Parsing
# notes", "Spaces before brackets").
import time

function twice (x)
  return 2 * x
end

function scale (x; by = 2)
  return x * by
end

f = function (a) return a + 1 end
v = [10, 20, 30]
A = [1, 2; 3, 4]

println (twice (4))
println(f (1), twice (twice (1)))
println(scale (3, by = 10), max (v), length (v))
println(time.format (1.5))

# Inside vector, matrix, list and record literals.
w = [twice (1), twice (2); f (0), sqrt (16.0)]
println(w [2, 2], size (w, 1))
l = {twice (3), abs (-2)}
println(l)
r = {a: twice (7), b: v [2]}
println(r.a, r.b)

# Indexing, and a call in a one-line if.
println(v [3], A [2, 1], v [end])
if twice (2) == 4 println("one-line if") end

# Inside brackets a line break is a space too.
println([twice
         (5), 1][1])
