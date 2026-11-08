#! error: FieldError
try
  error("x")
catch e
  println(e.nonexistent)
end
