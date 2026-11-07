#! error: UserError
function origin()
  error("original")
end
try
  origin()
catch e
  print("re-raising")
  error(e)
end
