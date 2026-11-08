#! error: IndexError
try
  error("x")
catch e
  println(e.trace[0])
end
