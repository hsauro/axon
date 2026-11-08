# print leaves the line open; println ends it.
print("a")
print("b", 1)
println()
println("c", 2.5)
print()
println("d")
print("x"); println("y")

function row(n: int)
  for k in 1:n
    print(k)
    if k < n
      print(",")
    end
  end
  println()
end
row(3)
println((__jit_mode() != "off") == __jit_compiled(row))
