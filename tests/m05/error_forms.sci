try
  error("plain text")
catch e
  println(e.kind, e.message)
end
try
  error("SingularMatrix", "matrix is singular")
catch e
  println(e.kind, e.message)
end
try
  error("MyOwnKind", "any kind name is allowed")
catch e
  println(e.kind)
end

# Re-raising keeps kind, message and trace unchanged
function fails()
  error("DomainError", "deep problem")
end
try
  try
    fails()
  catch e
    error(e)
  end
catch again
  println(again.kind, again.message, length(again.trace))
  println(again.trace[1].line, again.trace[1].function, again.trace[2].line)
end

# The reference's pattern: handle one kind, re-raise the rest
function handle_only_domain(thunk)
  try
    thunk()
  catch err
    if err.kind != "DomainError"
      error(err)
    end
    return "handled " + err.kind
  end
  return "no error"
end
println(handle_only_domain(function() error("DomainError", "x") end))
try
  handle_only_domain(function() error("TypeError", "y") end)
catch err
  println("propagated", err.kind)
end
