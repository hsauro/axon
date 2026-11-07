#! error: TypeError
function f(x: int)
  return x
end
function g()
  return f("text")
end
g()
