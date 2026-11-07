from testing import approx
A = [1, 1; 1, 0]
print(A ^ 10, A ^ 0)
print(eltype(A ^ 3), eltype(A ^ -1))
print(approx(A ^ -2 * A ^ 2, eye(2)))
S = [4.0, 1.0; 1.0, 3.0]
R = S ^ 0.5
print(eltype(R), approx(R * R, S))
print(approx(S ^ 2.0, S * S))
N = [1.0, 2.0; 3.0, 4.0]
H = N ^ 0.5
print(eltype(H), approx(H * H, N + 0i))
print(approx([2 + 0i, 0; 0, 3] ^ 2, [4 + 0i, 0; 0, 9]))
