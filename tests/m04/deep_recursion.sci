function depth(n)
  if n == 0 return 0 end
  return 1 + depth(n - 1)
end
println(depth(9000))
