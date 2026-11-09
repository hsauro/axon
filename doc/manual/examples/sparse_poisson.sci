## A sparse system: the 1-D Poisson equation -u'' = 1 on (0, 1), u(0) = u(1) = 0.

n = 2000
h = 1.0 / (n + 1)

# Triplets (i, j, value) for the tridiagonal matrix with 2 on the diagonal
# and -1 beside it.
i = [1:n; 1:n-1; 2:n]
j = [1:n; 2:n; 1:n-1]
v = [2.0 * ones(n); -ones(n - 1); -ones(n - 1)]
S = sparse(i, j, v, n, n) / h^2

println("stored entries:", nnz(S), "of", n * n)
u = S \ ones(n)                    # the sparse LU solves it

# The exact solution is x (1 - x) / 2; compare at the middle.
mid = div(n, 2)
xm = mid * h
println("u(0.5) about", format(u[mid], 6), " exact", format(xm * (1 - xm) / 2, 6))
