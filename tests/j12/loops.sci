# Top-level loops compiled (J12). Each case prints its results, then whether
# loops ran compiled as often as expected (always true with the JIT off).
# The suite runs this file in every JIT mode, so the compiled results are
# checked against the same expectations as the interpreted ones.

function ran(mark, n)
  return __jit_mode() == "off" or __jit_loops() - mark == n
end

# Prints its argument; a keyword parameter keeps it interpreted.
function show(x; prefix = "")
  println(prefix + string(x))
end

# A sum, and an array changed element by element without being copied.
m = __jit_loops()
c = __copies()
total = 0
a = zeros(5)
for i in 1:5
  total = total + i
  a[i] = i * i
end
println(string(total) + " " + string(a[5]) + " " + string(__copies() - c))
println(ran(m, 1))

# An array shared with another variable is copied once, at the first write.
m = __jit_loops()
b = a
c = __copies()
for i in 1:5
  a[i] = 0.0
end
println(string(b[5]) + " " + string(a[5]) + " " + string(__copies() - c))
println(ran(m, 1))

# while, and a variable the loop creates.
m = __jit_loops()
k = 0
while k < 7
  k = k + 2
  last = k * 0.5
end
println(string(k) + " " + string(last))
println(ran(m, 1))

# A loop that never assigns a name does not create it.
for i in 1:0
  never = 1
end
try
  println(never)
catch e
  println("never is not defined")
end

# A variable holding nothing, set by the loop.
m = __jit_loops()
r = nothing
for i in 1:3
  r = i * 1.5
end
println(r)
println(ran(m, 1))

# Declared variables widen what is assigned to them.
m = __jit_loops()
x: real = 0
n: int = 0
for i in 1:4
  x = i
  n = n + 1
end
println(string(x) + " " + string(n))
println(ran(m, 1))

# Strings, records and lists from outside.
m = __jit_loops()
s = ""
p = {x: 0.0, n: 0}
items = {0}
for i in 1:3
  s = s + string(i)
  p.x = p.x + 0.5
  p.n = p.n + 1
  items = append(items, i * 10)
end
println(s + " " + string(p.x) + " " + string(p.n) + " " + string(length(items)) + " " +
        string(items[4]))
println(ran(m, 1))

# The outer loop calls a function that runs interpreted, so it is
# interpreted; its inner loop, which reads the outer loop's variable, is
# compiled once and run three times.
m = __jit_loops()
for row in 1:3
  acc = 0
  for col in 1:row
    acc = acc + row * col
  end
  show(acc)
end
println(ran(m, 3))

# A loop that uses variables from outside and calls a function that runs
# interpreted stays interpreted.
m = __jit_loops()
t = 0
for i in 1:3
  t = t + i
  show(t, prefix = "t = ")
end
println(ran(m, 0))

# One that uses none may call it.
m = __jit_loops()
for i in 1:2
  show(i * 10)
end
println(ran(m, 1))

# A variable whose type changes keeps the loop interpreted.
m = __jit_loops()
q = 0
for i in 1:3
  q = q + 0.5
end
println(q)
println(ran(m, 0))

# Inside a top-level if.
m = __jit_loops()
if total > 0
  u = 1
  for i in 1:10
    u = u * 2
  end
  println(u)
end
println(ran(m, 1))

# An error stops the loop; the variables hold what they held then.
m = __jit_loops()
total = 0
try
  for i in 1:10
    total = total + i
    if i == 4
      error("stop")
    end
  end
catch e
  println(total)
end
println(ran(m, 1))

# An assignment that fails leaves the variable as it was.
big = 4611686018427387904
try
  for i in 1:3
    big = big * 2
  end
catch e
  println(big)
end
