# Rule 2: local creates a variable in the innermost scope, shadowing outer ones.
x = 1
if true
  local x = 2
  x = x + 10
  print(x)
end
print(x)
function f()
  y = "outer"
  if true
    local y = "inner"
    print(y)
  end
  return y
end
print(f())
