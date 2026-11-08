# Rule 2: local creates a variable in the innermost scope, shadowing outer ones.
x = 1
if true
  local x = 2
  x = x + 10
  println(x)
end
println(x)
function f()
  y = "outer"
  if true
    local y = "inner"
    println(y)
  end
  return y
end
println(f())
