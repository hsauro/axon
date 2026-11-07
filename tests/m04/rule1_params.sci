# Rule 1: parameters are local to their function.
x = "module"
function f(x)
  x = "changed"
  return x
end
print(f("arg"), x)
g = function(x) x = 0; return x end
print(g(5), x)
