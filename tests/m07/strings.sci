s = "héllo wörld"
print(s[1], s[2], s[end], length(s))
print(s[1:5], s[7:end])
print(s[[1, 1, 2]])
n = 0
for c in "a😀b"
  n = n + 1
  print(c)
end
print(n, "a😀b"[2])
