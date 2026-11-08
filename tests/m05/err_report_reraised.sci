#! error: UserError
function origin()
  error("original")
end
try
  origin()
catch e
  println("re-raising")
  error(e)
end
