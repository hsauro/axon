# Whole-array operations run in typed loops; they must give exactly what the
# scalar operators give element by element.
import random
random.seed(7)

n = 2000
v = random.normal(0.0, 3.0, n)
w = random.uniform(-2.0, 2.0, n)
w[5] = 0.0
v[9] = 0.0 / 0.0
iv = random.randint(-50, 50, n)
jv = random.randint(1, 9, n)

# Exactly equal, element by element, with NaN matching NaN.
function same_as(a, b)
  if length(a) != length(b) return false end
  for k in 1:length(a)
    x = a[k]
    y = b[k]
    if not (x == y or (x != x and y != y)) return false end
  end
  return true
end

# Element by element, through the scalar operators.
function each(op, a, b)
  r = zeros(length(a))
  for k in 1:length(a)
    if op == "+" r[k] = a[k] + b[k] end
    if op == "-" r[k] = a[k] - b[k] end
    if op == "*" r[k] = a[k] * b[k] end
    if op == "/" r[k] = a[k] / b[k] end
    if op == "^" r[k] = a[k] ^ b[k] end
  end
  return r
end

println(same_as(v + w, each("+", v, w)), same_as(v - w, each("-", v, w)),
        same_as(v .* w, each("*", v, w)), same_as(v ./ w, each("/", v, w)))
println(same_as(abs(v) .^ w, each("^", abs(v), w)), same_as(v .^ 2.0, each("^", v, 2.0 * ones(n))),
        same_as(w .^ 0.5, each("^", w, 0.5 * ones(n))))
println(same_as(iv + 0.5, each("+", iv, 0.5 * ones(n))), same_as(iv ./ jv, each("/", iv, jv)),
        same_as(2.0 - v, each("-", 2.0 * ones(n), v)))

# Comparisons, with NaN unordered and unequal.
lt = v < w
ne = v != w
same = true
for k in 1:n
  if lt[k] != (v[k] < w[k]) or ne[k] != (v[k] != w[k]) same = false end
end
println(same, lt[9], ne[9], (v == v)[9], eltype(lt))

# Elementary functions, sums, min and max.
e = exp(w)
ok = true
for k in 1:n
  if e[k] != exp(w[k]) ok = false end
end
s = 0.0
si = 0
for k in 1:n
  s = s + w[k]
  si = si + iv[k]
end
println(ok, sum(w) == s, sum(iv) == si, typeof(sum(iv)), max(w) == sort(w)[end], min(w) == sort(w)[1])
println(max(v), min([3; 7; -2]), max([3; 7; -2]))

# Sorting agrees with sorting the same numbers as a list (the general route).
lw = {}
for k in 1:n
  lw = append(lw, w[k])
end
sl = sort(lw)
sv = sort(w)
ok = true
for k in 1:n
  if sl[k] != sv[k] ok = false end
end
println(ok, isequal(sortperm(w), sortperm(lw)), isequal(sortperm(iv, "descend"), sortperm(iv + 0.0, "descend")))
# With NaN and descending, as the list route orders them.
lv = {}
for k in 1:n
  lv = append(lv, v[k])
end
lv[3] = -0.0
v[3] = -0.0
v[4] = 0.0
lv[4] = 0.0
function same_bits(a, l)
  for k in 1:length(a)
    x = a[k]
    y = l[k]
    if not ((x == y and 1 / x == 1 / y) or (x != x and y != y)) return false end
  end
  return true
end
println(same_bits(sort(v), sort(lv)), same_bits(sort(v, "descend"), sort(lv, "descend")),
        isequal(sortperm(v, "descend"), sortperm(lv, "descend")), sort(v)[end], sort(v, "descend")[end])

# Element types and shapes.
println(eltype([1; 2] + [3; 4]), eltype([1; 2] / 2), eltype([true; false] + [true; true]),
        eltype(-[true; false]), eltype([1; 2] .^ 2), eltype([2; 3] .^ -1))
println(eltype(zeros(0) + 1), eltype([1; 2][1:0] + 1), eltype(exp([1; 2][1:0])), eltype(exp([1; 2])))
function shape(a)
  [r, c] = size(a)
  return typeof(a) + " " + string(r) + "x" + string(c)
end
println(shape([1.0; 2.0] + [10.0, 20.0, 30.0]), shape([1.0, 2.0] .* 3), shape([1.0; 2.0] .* 3))
println(((1:3) + 0.5)')
println((-2.0) .^ [0.5; 2.0])

# Sums along a dimension, and products.
M = [1.0, 2.0, 3.0; 4.0, 5.0, 6.0]
println(sum(M, 1), sum(M, 2), prod([1; 2; 3; 4]), prod(M))

# Signed zeros keep their order in a sort (it is stable).
z = sort([0.0; -0.0])
println(1 / z[1], 1 / z[2])

# Integer overflow is still caught, in elementwise operators and sums.
big = 9223372036854775807
for f in {function() return [1; big] + 1 end, function() return -[1; -big - 1] end,
          function() return sum([big; 1]) end, function() return [2; big] .* 2 end}
  try
    f()
  catch err
    println(err.kind, err.message)
  end
end
