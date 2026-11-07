#! error: FieldError
try
  error("x")
catch e
  print(e.nonexistent)
end
