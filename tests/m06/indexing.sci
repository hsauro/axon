A = [1, 2, 3; 4, 5, 6; 7, 8, 9]
print(A[2, 3], A[1, 1], A[end, end], A[end, 1])
print(A[2, :])
print(A[:, 2])
print(A[1:2, 2:3])
print(A[5], A[end])
print(A[[1, 9]])
print(A[:, [1, 3]])
print(A[[3, 1], 1])
print(A[A > 6])
print(A[1:end-1, 3])
v = [10; 20; 30; 40]
print(v[2], v[end], v[end - 1])
print(v[2:3])
print(v[[4, 4, 1]])
print(v[v > 15])
print(v[:])
B = [5; 1; 2]
print(v[B[end]], A[B[end], end])
print(A[:])
r = 1:5
print(r[2], r[end])
print(length(A[1:0, :]))
