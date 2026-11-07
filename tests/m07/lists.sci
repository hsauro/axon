l = {1, "two", 3.0, [1, 2]}
print(l)
print(l[1], l[2], l[end - 1], length(l))
print(l[2:3])
print(l[[4, 1]])
print(l[[true, false, true, false]])
e = {}
print(e, length(e), typeof(e))
l2 = append(l, {5})
print(length(l), length(l2), l2[end])
for x in {10, "a", true}
  print(x)
end
m = {1, 2, 3}
m[2] = "changed"
print(m)
m[1:2] = {"x", "y"}
print(m)
nested = {{1, 2}, {3, {4, 5}}}
print(nested[2][2][1])
nested[2][2][1] = 40
print(nested)
print({1, 2} == {1, 2}, {1, 2} == {2, 1}, isequal({1, {2}}, {1, {2}}), {1} != {1.0})
