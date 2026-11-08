from testing import approx
A = [1, 1; 1, 0]
println(A ^ 10, A ^ 0)
println(eltype(A ^ 3), eltype(A ^ -1))
println(approx(A ^ -2 * A ^ 2, eye(2)))
S = [4.0, 1.0; 1.0, 3.0]
R = S ^ 0.5
println(eltype(R), approx(R * R, S))
println(approx(S ^ 2.0, S * S))
N = [1.0, 2.0; 3.0, 4.0]
H = N ^ 0.5
println(eltype(H), approx(H * H, N + 0i))
println(approx([2 + 0i, 0; 0, 3] ^ 2, [4 + 0i, 0; 0, 9]))
