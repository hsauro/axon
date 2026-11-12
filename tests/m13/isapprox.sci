# isapprox(a, b; rtol, atol): |x - y| <= max(atol, rtol * max(|x|, |y|)),
# for numbers and element by element for arrays of one shape; the default
# rtol is the square root of the double epsilon, about 1.5e-8.
A = [1.0, 2.0; 3.0, 4.0]
println(isapprox(A, A + 1e-12), isapprox(A, A + 1e-3))
println(isapprox(A, A + 1e-3, rtol = 1e-2), isapprox(A, A + 1e-3, atol = 0.01))
println(isapprox(0.1 + 0.2, 0.3), 0.1 + 0.2 == 0.3)
println(isapprox(0.0, 1e-20), isapprox(0.0, 1e-20, atol = 1e-12))
println(isapprox(1, 1.0), isapprox([1; 2; 3], 1:3), isapprox(1.0 + 2.0i, 1.0 + 2.0i + 1e-12))

# Shapes must match; a number is not an array.
println(isapprox(A, [1.0, 2.0, 3.0, 4.0]), isapprox([1.0], 1.0))

# Infinities equal to themselves; NaN never close.
println(isapprox(1.0 / 0.0, 1.0 / 0.0), isapprox(0.0 / 0.0, 0.0 / 0.0))

# Compiled code calls it too.
function close_enough(x, y)
  return isapprox(x, y)
end
println(close_enough(2.0, 2.0 + 1e-10), close_enough(A, A * 1.1))

# Errors.
try
  isapprox(A, A, tol = 1e-3)
catch err
  println(err.kind, err.message)
end
try
  isapprox(A, A, rtol = -1.0)
catch err
  println(err.kind, err.message)
end
try
  isapprox("a", "a")
catch err
  println(err.kind, err.message)
end
