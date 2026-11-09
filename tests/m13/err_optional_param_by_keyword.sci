#! error: ArgumentError
# An optional positional parameter is still positional, not a keyword.
f = function(a, b = 1)
  return a
end
f(1, b = 2)
