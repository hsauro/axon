# Named functions, called before their definition
println(square(4), cube(2))
function square(x)
  return x * x
end
function cube(x) return x * square(x) end

# Recursion and mutual recursion
function fact(n)
  if n <= 1 return 1 end
  return n * fact(n - 1)
end
function is_even(n)
  if n == 0 return true end
  return is_odd(n - 1)
end
function is_odd(n)
  if n == 0 return false end
  return is_even(n - 1)
end
println(fact(10), is_even(10), is_odd(7))

# Anonymous functions and functions as values
sq = function(x) return x^2 end
apply = function(f, x) return f(x) end
println(sq(3), apply(sq, 5), apply(sqrt, 16.0), apply(function(t) return t + 1 end, 1))
compose = function(f, g) return function(x) return f(g(x)) end end
inc_then_sq = compose(sq, function(x) return x + 1 end)
println(inc_then_sq(2))

# No return value gives nothing
function noop() end
function early(x)
  if x > 0 return end
  println("not positive")
end
println(noop(), early(1))
early(-1)

# Function values display and compare
println(square, sq == sq, square == cube, typeof(square), typeof(sq))

# Redefinition replaces: the last definition wins
function g() return 1 end
function g() return 2 end
println(g())

# A call used as a statement discards its values
function two() return 1, 2 end
two()
println("done")
