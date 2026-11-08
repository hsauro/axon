A = [1, 2, 3; 4, 5, 6; 7, 8, 9]
println(A[2, 3], A[1, 1], A[end, end], A[end, 1])
println(A[2, :])
println(A[:, 2])
println(A[1:2, 2:3])
println(A[5], A[end])
println(A[[1, 9]])
println(A[:, [1, 3]])
println(A[[3, 1], 1])
println(A[A > 6])
println(A[1:end-1, 3])
v = [10; 20; 30; 40]
println(v[2], v[end], v[end - 1])
println(v[2:3])
println(v[[4, 4, 1]])
println(v[v > 15])
println(v[:])
B = [5; 1; 2]
println(v[B[end]], A[B[end], end])
println(A[:])
r = 1:5
println(r[2], r[end])
println(length(A[1:0, :]))
