#! error: NameError
try
  error("x")
catch err
end
println(err)
