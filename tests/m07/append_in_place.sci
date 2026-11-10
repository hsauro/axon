# v = append(v, x) grows v in place when nothing else shares its value.
# Whatever shares the value before the append must not see the new element.

# Lists: a copy taken earlier keeps its length.
l = {1, 2}
m = l
l = append(l, 3)
l = append(l, "four")
println(l, m)

# A list inside another value is shared with it.
holder = {l}
l = append(l, 5)
println(length(l), length(holder[1]))

# Vectors, including a whole vector or a range appended at once.
v = [1.0; 2.0]
w = v
v = append(v, 3)
v = append(v, [4.0; 5.0])
v = append(v, 6:7)
println(v')
println(w')

# Appending a wider element widens the vector, as before.
iv = [1; 2]
iv = append(iv, 2.5)
println(typeof(iv[3]), iv[3], length(iv))

# x may read v; it sees v before the append.
k = zeros(0)
for j in 1:4
  k = append(k, length(k))
end
println(k')

# Appending v to itself.
s = [1; 2]
s = append(s, s)
println(s')

# Inside functions, with a typed variable.
function squares(n)
  r: vector{real} = zeros(0)
  for j in 1:n
    r = append(r, j * j)
  end
  return r
end
println(squares(5)')

# A typed variable that would have to narrow keeps its old value.
t: vector{int} = [1; 2]
try
  t = append(t, 0.5)
catch err
  println(err.kind)
end
println(t')

# A failed append leaves the variable as it was.
n = 7
try
  n = append(n, 1)
catch err
  println(err.kind)
end
println(n)

# Evaluating x may assign v; the append uses v's value from before.
g = {1}
function bump()
  global g
  g = {100}
  return 2
end
g = append(g, bump())
println(g)

# A user function called append is called, not the built-in.
function outer()
  append = function(a, b) return "mine" end
  q = {1}
  q = append(q, 2)
  return q
end
println(outer())

# Building a long list stays linear: 20000 appends.
big = {}
for j in 1:20000
  big = append(big, j)
end
println(length(big), big[end])
