#! error: IndexError
try
  error("x")
catch e
  println(e.trace[1.0])
end
