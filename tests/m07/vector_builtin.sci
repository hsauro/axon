# vector() and vector(x): an empty vector, and conversions to a vector.
v = vector()
println(typeof(v), eltype(v), length(v))

# A list of numbers: the element type is the widest present.
println(vector({1.0, 2.5, 3.0})')
println(vector({1, 2, 3})', eltype(vector({1, 2, 3})))
println(eltype(vector({1, 2.5})), eltype(vector({true, false})), eltype(vector({})))

# Ranges, matrices (column by column) and numbers.
println(vector(2:4)', vector(0:0.5:1)')
println(vector([1.0, 2; 3, 4])')
println(typeof(vector(zeros(3, 1))), length(vector(zeros(3, 1))), vector([1, 2, 3]')')
println(vector(5)', vector(2.5)', typeof(vector(1 + 2i)), eltype(vector(1 + 2i)))

# A vector comes back unchanged.
w = [1.0; 2.0]
println(isequal(vector(w), w), typeof(vector(w)))

# Growing a vector from vector() with append.
ts = vector()
for k in 1:3
  ts = append(ts, k * 0.5)
end
println(ts')
