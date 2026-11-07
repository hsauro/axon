function area(r: real): real
  return 3.0 * r^2
end
print(area(2), area(1.5))
function half(n: int): real return n / 2 end
print(half(5), half(true))
x: real = 1
print(x, typeof(x))
x = 7
print(x, typeof(x))
z: complex = 2
print(z)
s: string = "a"
s = s + "b"
print(s)
f: function = sqrt
print(f(9.0))
function maybe(flag: bool): nothing
  if flag print("yes") end
end
print(maybe(true))
local q: int = 3
print(q)
