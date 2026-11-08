## Linear algebra: solving systems, determinants, eigenvalues.

import linalg

A = [4.0, -2.0, 1.0;
     -2.0, 4.0, -2.0;
     1.0, -2.0, 4.0]
b = [11.0; -16.0; 17.0]

x = A \ b
println("solution of A x = b:")
println(x)
println("residual:", max(abs(A * x - b)))

println("det(A) =", linalg.det(A))
println("eigenvalues:")
println(linalg.eig(A))

# Matrix powers and the matrix exponential.
println("A^2 =")
println(A ^ 2)
println("expm of a rotation generator:")
println(linalg.expm([0.0, -1.0; 1.0, 0.0]))
