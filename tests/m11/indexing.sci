S = sparse([1, 3, 2, 1], [1, 1, 2, 3], [4.0, -1.0, 2.5, 7.0], 3, 3)
# [4 0 7; 0 2.5 0; -1 0 0]
print(S[1, 1], S[2, 1], S[3, 1], S[1, 3])
# Linear indices run down the columns.
print(S[3], S[7], S[8])
# Two indices select a sparse submatrix; one non-scalar index a dense vector.
print(S[1, :])
print(S[2:3, 1:2])
print(S[[1, 3]])

# Assigning zero removes an entry; a new position adds one.
S[2, 2] = 0
S[2, 3] = 5
print(S)
S[1, :] = [1, 2, 3]
print(S)
S[1:2, 3] = [0; 0]
print(nnz(S), S[1, 3])
# A complex value makes the matrix complex.
S[3, 1] = 1i
print(eltype(S), S[3, 1])

# Copy-on-write: a shared matrix is copied once, on the first write.
T = speye(3)
U = T
n0 = __copies()
U[1, 1] = 9
U[2, 2] = 8
print(__copies() - n0, T[1, 1], U[1, 1], U[2, 2])
function bump(M)
  M[1, 1] = 100
  return M
end
V = bump(T)
print(T[1, 1], V[1, 1])

# Annotations.
x: sparse = speye(2)
y: sparse{complex} = speye(2)
print(typeof(x), eltype(y))
