#! error: NameError
try
  error("x")
catch e
end
println(e)
