## Linear algebra: solving, factorising and least squares.

import linalg

A = [4.0, 1.0, 2.0;
     1.0, 3.0, 0.0;
     2.0, 0.0, 5.0]
b = [1.0; 2.0; 3.0]

x = A \ b                          # solve A x = b
println("x =", x')
println("residual:", linalg.norm(A * x - b))
println("det:", linalg.det(A))

# A is symmetric positive definite: real eigenvalues, and a Cholesky factor.
println("eigenvalues:", sort(linalg.eig(A))')
R = linalg.chol(A)
println("R'R matches A:", linalg.norm(R' * R - A) < 1e-12)

# The singular values, largest first.
[U, s, V] = linalg.svd(A)
println("singular values:", s')

# An overdetermined system: least squares.
M = [1.0, 1.0; 1.0, 2.0; 1.0, 3.0; 1.0, 4.0]
y = [6.0; 5.0; 7.0; 10.0]
println("least squares:", (M \ y)')
