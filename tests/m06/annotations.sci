function norm1(v: vector): real
  return sum(abs(v)) * 1.0
end
println(norm1([1; -2; 3]), norm1(1:3))
M: matrix{real} = [1, 2; 3, 4]
println(M)
M[1, 1] = 7
println(M[1, 1], typeof(M))
x: vector{complex} = [1; 2]
println(x)
