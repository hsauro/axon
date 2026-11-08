# Rule 1: parameters are local to their function.
x = "module"
function f(x)
  x = "changed"
  return x
end
println(f("arg"), x)
g = function(x) x = 0; return x end
println(g(5), x)
