function kind_of(thunk)
  try
    thunk()
  catch err
    return err.kind
  end
  return "no error"
end
function forever(n) return forever(n + 1) end
println(kind_of(function() sqrt(1, 2) end))
println(kind_of(function() div(1, 0) end))
function field_error()
  try
    error("x")
  catch e
    return e.nope
  end
end
function index_error()
  try
    error("x")
  catch e
    return e.trace[5]
  end
end
println(kind_of(field_error))
println(kind_of(index_error))
println(kind_of(function() not_defined end))
println(kind_of(function() 9223372036854775807 + 1 end))
println(kind_of(function() forever(0) end))
println(kind_of(function() "a" + 1 end))
println(kind_of(function() error("u") end))
println(kind_of(function() 1 + 1 end))
