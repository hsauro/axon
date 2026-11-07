function bump(x)
  x = x + 1
  return x
end
a = 1
b = bump(a)
print(a, b)
function shout(s)
  s = s + "!"
  return s
end
t = "hi"
print(shout(t), t)
