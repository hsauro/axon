A = [1, 2; 3, 4]
B = [5, 6; 7, 8]
println(A * B)
v = [1; 1]
println(A * v)
println(v' * v, typeof(v' * v))
println(v * v')
println([1, 2, 3] * [4; 5; 6])
println(A * 2.5)
C = [1, 2, 3; 4, 5, 6]
println(C * [1; 0; 1])
println([1, 2; 3, 4] * [1i; 1])
