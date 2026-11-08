try
  error("x")
catch e
  t = e.trace
  println(length(t), t[1].line, t[end].line, t[length(t)].line)
  println(t[1])
end
println(length("abc"), length("αβ😀"), length(""), length(1:10), length(5:1))
