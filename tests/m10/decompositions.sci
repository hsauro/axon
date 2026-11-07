import linalg
from testing import approx, approx_set, orthonormal
A = [4.0, 1.0, 2.0; 1.0, 3.0, 0.0; 2.0, 0.0, 5.0]
M = [1.0, 2.0; 3.0, 4.0; 5.0, 6.0]
C = [2 + 1i, 1 - 1i; 0.5i, 3]

# det and inv
print(approx(linalg.det([1, 2; 3, 4]), -2.0), approx(linalg.det(A), 43.0))
print(approx(linalg.det(C), (2 + 1i) * 3 - (1 - 1i) * 0.5i), approx(linalg.det([1, 2; 2, 4]), 0.0))
print(approx(linalg.inv(A) * A, eye(3)), approx(linalg.inv(C) * C, eye(2) + 0i))

# eig
print(approx_set(linalg.eig([2, 0; 0, 3]), [2.0; 3.0]), eltype(linalg.eig([2, 0; 0, 3])))
print(approx_set(linalg.eig([0, -1; 1, 0]), [1i; -1i]), eltype(linalg.eig([0, -1; 1, 0])))
[w, V] = linalg.eig(A, vectors = true)
print(approx(A * V, V * [w[1], 0, 0; 0, w[2], 0; 0, 0, w[3]]))
[w, V] = linalg.eig([0.0, -2.0; 1.0, 0.0], vectors = true)
print(eltype(V), approx([0.0, -2.0; 1.0, 0.0] * V, V * [w[1], 0; 0, w[2]]))
[w, V] = linalg.eig(C, vectors = true)
print(approx(C * V, V * [w[1], 0; 0, w[2]]))

# svd
[U, s, V] = linalg.svd(M)
print(size(U, 1), size(U, 2), length(s), size(V, 1), orthonormal(U), orthonormal(V))
print(approx(U[:, 1:2] * [s[1], 0; 0, s[2]] * V', M), s[1] >= s[2])
[U, s, V] = linalg.svd(C)
print(approx(U * [s[1], 0; 0, s[2]] * adjoint(V), C))

# qr
[Q, R] = linalg.qr(M)
print(size(Q, 1), size(Q, 2), size(R, 1), size(R, 2), orthonormal(Q), R[2, 1] == 0)
print(approx(Q * R, M))
[Q, R] = linalg.qr(C)
print(approx(Q * R, C), orthonormal(Q))

# lu
[L, U] = linalg.lu(A)
print(approx(L * U, A), U[2, 1] == 0 and U[3, 1] == 0 and U[3, 2] == 0)
[L, U] = linalg.lu(M)
print(approx(L * U, M))

# chol
R = linalg.chol(A)
print(approx(R' * R, A), R[2, 1] == 0)
P = [2.0, 1i; -1i, 2.0]
R = linalg.chol(P)
print(approx(adjoint(R) * R, P))

# rank, null, norm
print(linalg.rank(A), linalg.rank([1, 2; 2, 4]), linalg.rank(M), linalg.rank(zeros(2, 2)))
N = linalg.null([1.0, 2.0; 2.0, 4.0])
print(size(N, 2), approx([1.0, 2.0; 2.0, 4.0] * N, zeros(2, 1)))
print(size(linalg.null(A), 2))
print(linalg.norm([3; 4]), linalg.norm([3; -4], p = 1), linalg.norm([3; -4], p = "inf"))
print(approx(linalg.norm([1, 2; 3, 4], p = "fro"), sqrt(30.0)), approx(linalg.norm([1, 2; 3, 4], p = 1), 6.0))
print(approx(linalg.norm([1, 2; 3, 4], p = "inf"), 7.0))
print(approx(linalg.norm([1.0, 2.0; 3.0, 4.0]), 5.464985704219043))

# expm
E = linalg.expm([0.0, 1.0; -1.0, 0.0])
print(approx(E, [cos(1.0), sin(1.0); -sin(1.0), cos(1.0)]))
print(approx(linalg.expm([1.0, 0.0; 0.0, 2.0]), [exp(1.0), 0.0; 0.0, exp(2.0)]))
print(approx(linalg.expm(zeros(3, 3)), eye(3)))
print(approx(linalg.expm([0.0, 6.0; 0.0, 0.0]), [1.0, 6.0; 0.0, 1.0]))
print(approx(linalg.expm(1i * [0.0, 1.0; 1.0, 0.0]), [cos(1.0), 1i * sin(1.0); 1i * sin(1.0), cos(1.0)]))
big = linalg.expm([-50.0, 49.0; 49.0, -50.0])
print(approx(big, 0.5 * [exp(-1.0) + exp(-99.0), exp(-1.0) - exp(-99.0); exp(-1.0) - exp(-99.0), exp(-1.0) + exp(-99.0)], tol = 1e-8))

# solve and lstsq
print(approx(linalg.solve(A, [1.0; 2.0; 3.0]), A \ [1.0; 2.0; 3.0]))
print(approx(linalg.lstsq([1.0, 1.0; 1.0, 2.0; 1.0, 3.0], [1.0; 2.0; 2.0]), [2.0 / 3.0; 0.5]))
print(approx(linalg.lstsq([1.0, 2.0; 2.0, 4.0], [1.0; 2.0]), [0.2; 0.4]))
