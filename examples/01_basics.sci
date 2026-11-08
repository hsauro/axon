## Basics: values, functions, loops and printing.
## Press F9 to run. Put the caret on a name and press F1 for its help.

x = 3
y = 2.5
name = "Axon"
print("Hello from", name)
print("x * y =", x * y, "  x / 2 =", x / 2, "  div(x, 2) =", div(x, 2))

## The factorial of n, computed with a loop.
function fact(n)
  result = 1
  for k in 1:n
    result = result * k
  end
  return result
end

for n in 1:6
  print(string(n) + "! =", fact(n))
end

# Functions are values; this one captures y.
scale = function(v) return y * v end
print("scale(4) =", scale(4))

# Complex numbers: sqrt of a negative real is NaN; of a complex, a complex.
print("sqrt(-4.0) =", sqrt(-4.0), "  sqrt(-4 + 0i) =", sqrt(-4 + 0i))
