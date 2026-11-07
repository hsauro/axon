if true
  a = 1
end
print(a)
for i in 1:2
  local b = i
  c = i
end
print(c)
d = 1
if true
  local d = 2
  print(d)
end
print(d)
e = 1
for i in 1:3
  e = e + i
end
print(e)
