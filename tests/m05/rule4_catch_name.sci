# Scope rule 4: the name bound by catch is local to the catch block.
err = "outer value"
try
  error("boom")
catch err
  println(err.message)
end
println(err)
