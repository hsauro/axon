# sparse(i, j, v, m, n), sparse(i, j, v), sparse(A), speye, nnz, full
S = sparse([1, 3, 2, 1], [1, 1, 2, 3], [4.0, -1.0, 2.5, 7.0], 3, 3)
println(typeof(S), eltype(S), nnz(S), length(S))
[m, n] = size(S)
println(m, n)
println(S)

# Repeated pairs are summed; an entry that sums to zero is not stored.
# Without m and n the size comes from the largest indices.
D = sparse([1, 1, 2, 2], [1, 1, 2, 2], [1.0, 2.0, 3.0, -3.0])
println(D)

# int and bool values are stored as real; a scalar value fills every entry.
I = sparse([1, 2], [2, 1], 5)
println(eltype(I), I[1, 2], I[2, 1], I[1, 1])
println(sparse([2], [3], [true]))

# From a dense matrix, and back.
println(sparse([0, 2; 3, 0]))
F = full(S)
println(typeof(F), F[3, 1], F[2, 3])
println(isequal(full(sparse(F)), F))

println(speye(2))
println(speye(2, 3))
println(nnz([1, 0, 2; 0, 0, 3]), nnz(speye(4)))

C = sparse([1], [1], [1 + 2i], 2, 2)
println(eltype(C))
println(C)
