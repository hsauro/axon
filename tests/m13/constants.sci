# The constants pi and e: the doubles nearest to them, and shadowing.
println(format(pi, 15))
println(format(e, 15))
println(pi == 4 * atan(1.0))
println(e == exp(1.0))
println(cos(pi))

area = function(r)
  return pi * r^2
end
println(area(1.0) == pi)

# A program's own e hides the constant in its scope.
g = function()
  e = 3
  return e
end
println(g())
println(e > 2.7)
e = 0.5
println(e)
