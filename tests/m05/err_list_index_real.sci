#! error: IndexError
try
  error("x")
catch e
  print(e.trace[1.0])
end
