function norm1(v: vector): real
  return sum(abs(v)) * 1.0
end
print(norm1([1; -2; 3]), norm1(1:3))
M: matrix{real} = [1, 2; 3, 4]
print(M)
M[1, 1] = 7
print(M[1, 1], typeof(M))
x: vector{complex} = [1; 2]
print(x)
