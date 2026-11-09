#! error: SyntaxError
# Once a positional parameter has a default, the rest need one too.
f = function(a, b = 1, c)
  return a
end
