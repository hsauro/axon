#! error: TypeError
try
  error("x")
catch e
  error(e.trace[1])
end
