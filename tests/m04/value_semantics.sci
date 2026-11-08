function bump(x)
  x = x + 1
  return x
end
a = 1
b = bump(a)
println(a, b)
function shout(s)
  s = s + "!"
  return s
end
t = "hi"
println(shout(t), t)
