s = "héllo wörld"
println(s[1], s[2], s[end], length(s))
println(s[1:5], s[7:end])
println(s[[1, 1, 2]])
n = 0
for c in "a😀b"
  n = n + 1
  println(c)
end
println(n, "a😀b"[2])
