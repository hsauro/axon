# Rule 5: plain assignment finds the nearest existing variable, else creates it
# in the function's outermost scope.
if true
  made_in_if = "visible"
end
print(made_in_if)
function f()
  for i in 1:3
    total = i
  end
  return total
end
print(f())
# A closure assigns the enclosing function's variable
function counter()
  n = 0
  bump = function() n = n + 1 end
  bump(); bump(); bump()
  return n
end
print(counter())
# A variable created inside a closure stays local to the closure
function outer()
  inner = function() fresh = 1; return fresh end
  inner()
  return 0
end
print(outer())
