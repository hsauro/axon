## Linear algebra: solving systems, determinants, eigenvalues.

import linalg

A = [4.0, -2.0, 1.0;
     -2.0, 4.0, -2.0;
     1.0, -2.0, 4.0]
b = [11.0; -16.0; 17.0]

x = A \ b
print("solution of A x = b:")
print(x)
print("residual:", max(abs(A * x - b)))

print("det(A) =", linalg.det(A))
print("eigenvalues:")
print(linalg.eig(A))

# Matrix powers and the matrix exponential.
print("A^2 =")
print(A ^ 2)
print("expm of a rotation generator:")
print(linalg.expm([0.0, -1.0; 1.0, 0.0]))
