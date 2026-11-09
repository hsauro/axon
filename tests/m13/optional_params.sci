# Optional positional parameters: "= default" after a positional parameter.
f = function(a, b = 10)
  return a + b
end
println(f(1), f(1, 2))

# A default may use earlier parameters, and is evaluated at each call.
g = function(a, b = a * 2, c = a + b; scale = 1)
  return (a + b + c) * scale
end
println(g(1), g(1, 5), g(1, 5, 0), g(1, scale = 10))

# With annotations.
function area(w: real, h: real = w)
  return w * h
end
println(area(3), area(3, 2))

# A default of nothing, tested inside: one function, two call forms.
function span(a, b = nothing)
  if typeof(b) == "nothing"
    return a
  end
  return b - a
end
println(span(4), span(4, 9))

# Called from a loop, with and without the optional argument.
function step(s, by = 1)
  return s + by
end
function total(n)
  s = 0
  for k in 1:n
    s = step(s)
    s = step(s, 10)
  end
  return s
end
println(total(3))
