if true
  a = 1
end
println(a)
for i in 1:2
  local b = i
  c = i
end
println(c)
d = 1
if true
  local d = 2
  println(d)
end
println(d)
e = 1
for i in 1:3
  e = e + i
end
println(e)
