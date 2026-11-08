l = {1, "two", 3.0, [1, 2]}
println(l)
println(l[1], l[2], l[end - 1], length(l))
println(l[2:3])
println(l[[4, 1]])
println(l[[true, false, true, false]])
e = {}
println(e, length(e), typeof(e))
l2 = append(l, {5})
println(length(l), length(l2), l2[end])
for x in {10, "a", true}
  println(x)
end
m = {1, 2, 3}
m[2] = "changed"
println(m)
m[1:2] = {"x", "y"}
println(m)
nested = {{1, 2}, {3, {4, 5}}}
println(nested[2][2][1])
nested[2][2][1] = 40
println(nested)
println({1, 2} == {1, 2}, {1, 2} == {2, 1}, isequal({1, {2}}, {1, {2}}), {1} != {1.0})
