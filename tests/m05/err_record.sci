function inner(x)
  return x / missing_name
end
function outer(x)
  return inner(x) + 1
end
try
  outer(1)
catch err
  print(err.kind)
  print(err.message)
  print(typeof(err), typeof(err.trace), length(err.trace))
  t = err.trace
  print(t[1].file, t[1].line, t[1].col, t[1].function)
  print(t[2].file, t[2].line, t[2].col, t[2].function)
  print(t[end].file, t[end].line, t[end].col, t[end].function == "")
  print(err)
end
# A frame in an anonymous function
f = function() error("from a lambda") end
try
  f()
catch err
  print(err.trace[1].function, err.trace[1].line)
end
