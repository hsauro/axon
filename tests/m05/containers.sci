try
  error("x")
catch e
  t = e.trace
  print(length(t), t[1].line, t[end].line, t[length(t)].line)
  print(t[1])
end
print(length("abc"), length("αβ😀"), length(""), length(1:10), length(5:1))
