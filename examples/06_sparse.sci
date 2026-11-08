## Sparse matrices: a 1-D Poisson problem with 2000 unknowns.

n = 2000
h = 1.0 / (n + 1)
# -u'' = 1 on (0, 1), u(0) = u(1) = 0, by finite differences.
S = sparse([1:n; 2:n; 1:n-1], [1:n; 1:n-1; 2:n],
           [ones(n) * 2.0; -ones(n - 1); -ones(n - 1)], n, n) / h^2
println(S[1:3, 1:3])
println("stored entries:", nnz(S), " of", n * n)

u = S \ ones(n)
# The exact solution is x (1 - x) / 2; compare at the middle.
mid = div(n, 2)
x = mid * h
println("u at x =", x, ":", u[mid], " exact:", x * (1 - x) / 2)
