#! error: NameError
try
  error("x")
catch e
end
print(e)
