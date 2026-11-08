A = zeros(2, 3)
A[1, 2] = 5
A[2, :] = [1, 2, 3]
A[:, 3] = 9
println(A)
v = [1; 2; 3; 4]
v[2:3] = [20; 30]
v[v > 25] = 0
println(v)
v[1] = 1.5
println(v)
w = [1; 2]
w[2] = 1i
println(w)
M = [1, 2; 3, 4]
M[[1, 2], 1] = [10, 30]
println(M)
M[1:2, 1:2] = [5, 6; 7, 8]
println(M)
B = [true, false]
B[2] = true
println(B)
r = 1:3
r[2] = 20
println(r)
function two() return 7, 8 end
[M[1, 1], y] = two()
println(M[1, 1], y)
