import linalg
from testing import approx

# -x'' = 1 on a tridiagonal: x[i] = i (n + 1 - i) / 2.
n = 1000
S = sparse([1:n; 2:n; 1:n-1], [1:n; 1:n-1; 2:n], [ones(n) * 2.0; -ones(n - 1); -ones(n - 1)], n, n)
x = S \ ones(n)
exact = zeros(n)
for i in 1:n
  exact[i] = i * (n + 1 - i) / 2
end
print(typeof(x), approx(x, exact, tol = 1e-9))
# The minimum-degree order eliminates a path without fill-in: L and U each
# hold the n diagonal entries and n - 1 others.
[L, U] = splu(S)
print(nnz(L), nnz(U))

# A zero on the diagonal forces a row interchange: P = [0 2 0; 3 0 1; 0 1 4].
P = sparse([2, 1, 3, 2, 3], [1, 2, 2, 3, 3], [3.0, 2.0, 1.0, 1.0, 4.0])
b = P * [1.0; 2.0; 3.0]
print(approx(P \ b, [1.0; 2.0; 3.0]))
[L, U] = linalg.lu(P)
print(typeof(L), typeof(U), approx(full(L * U), full(P)))

# Several right-hand sides, a sparse right-hand side, and division on the right.
B = [1.0, 0.0; 0.0, 1.0; 1.0, 1.0]
X = P \ B
print(typeof(X), approx(full(P) * X, B))
print(typeof(P \ speye(3)), approx(full(P) * (P \ speye(3)), eye(3)))
Y = [1.0, 2.0, 3.0] / P
print(approx(Y * full(P), [1.0, 2.0, 3.0]))

# Complex systems: [2i 1; 0 4] x = [1; 4] has x = [0; 1].
C = sparse([1, 2, 1], [1, 2, 2], [2i, 4.0, 1.0])
z = C \ [1.0; 4.0]
print(eltype(z), approx(z, [0.0 + 0i; 1.0 + 0i]))

# A 2-D grid (unsymmetric, 400 unknowns) against the dense solver.
k = 20
I = zeros(5 * k * k)
J = zeros(5 * k * k)
V = zeros(5 * k * k)
e = 0
for c in 1:k
  for r in 1:k
    p = (c - 1) * k + r
    e = e + 1; I[e] = p; J[e] = p; V[e] = 4.0
    if r > 1 e = e + 1; I[e] = p; J[e] = p - 1; V[e] = -1.0 end
    if r < k e = e + 1; I[e] = p; J[e] = p + 1; V[e] = -1.5 end
    if c > 1 e = e + 1; I[e] = p; J[e] = p - k; V[e] = -1.0 end
    if c < k e = e + 1; I[e] = p; J[e] = p + k; V[e] = -0.5 end
  end
end
G = sparse(int(I[1:e]), int(J[1:e]), V[1:e], k * k, k * k)
rhs = linspace(1.0, 2.0, k * k)
print(nnz(G), approx(G \ rhs, full(G) \ rhs))

# Functions in linalg work on full(A).
D = sparse([1, 3, 2, 1], [1, 1, 2, 3], [4.0, -1.0, 2.5, 7.0], 3, 3)
print(approx(linalg.det(D), 17.5), approx(linalg.inv(D) * full(D), eye(3)))
