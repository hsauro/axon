# sparse(i, j, v, m, n), sparse(i, j, v), sparse(A), speye, nnz, full
S = sparse([1, 3, 2, 1], [1, 1, 2, 3], [4.0, -1.0, 2.5, 7.0], 3, 3)
print(typeof(S), eltype(S), nnz(S), length(S))
[m, n] = size(S)
print(m, n)
print(S)

# Repeated pairs are summed; an entry that sums to zero is not stored.
# Without m and n the size comes from the largest indices.
D = sparse([1, 1, 2, 2], [1, 1, 2, 2], [1.0, 2.0, 3.0, -3.0])
print(D)

# int and bool values are stored as real; a scalar value fills every entry.
I = sparse([1, 2], [2, 1], 5)
print(eltype(I), I[1, 2], I[2, 1], I[1, 1])
print(sparse([2], [3], [true]))

# From a dense matrix, and back.
print(sparse([0, 2; 3, 0]))
F = full(S)
print(typeof(F), F[3, 1], F[2, 3])
print(isequal(full(sparse(F)), F))

print(speye(2))
print(speye(2, 3))
print(nnz([1, 0, 2; 0, 0, 3]), nnz(speye(4)))

C = sparse([1], [1], [1 + 2i], 2, 2)
print(eltype(C))
print(C)
