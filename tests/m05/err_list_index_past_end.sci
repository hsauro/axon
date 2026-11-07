#! error: IndexError
try
  error("x")
catch e
  print(e.trace[2])
end
