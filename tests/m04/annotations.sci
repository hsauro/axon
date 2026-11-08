function area(r: real): real
  return 3.0 * r^2
end
println(area(2), area(1.5))
function half(n: int): real return n / 2 end
println(half(5), half(true))
x: real = 1
println(x, typeof(x))
x = 7
println(x, typeof(x))
z: complex = 2
println(z)
s: string = "a"
s = s + "b"
println(s)
f: function = sqrt
println(f(9.0))
function maybe(flag: bool): nothing
  if flag println("yes") end
end
println(maybe(true))
local q: int = 3
println(q)
