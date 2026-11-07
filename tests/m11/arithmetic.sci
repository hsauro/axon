A = sparse([1, 2, 2], [1, 1, 2], [1.0, 2.0, 3.0])      # [1 0; 2 3]
B = sparse([1, 2], [2, 2], [4.0, -3.0])                # [0 4; 0 -3]

# Sparse with sparse stays sparse; a sum that cancels drops the entry.
print(A + B)
print(A - B)
print(A .* B)
print(A * B)

# A scalar with *, / and the elementwise forms.
print(2 * A)
print(A / 2)
print(typeof(A * 2), typeof(A ./ 2), typeof(2 .* A))
print(-B)

# Transposes, and powers by repeated multiplication.
print(A')
C = sparse([1, 2], [1, 2], [1i, 2.0])
print(adjoint(C))
print(A ^ 2)
print(typeof(A ^ 0), nnz(A ^ 0))

# Everything that fills in the zeros is dense.
print(typeof(A + 1), typeof(A ./ B), typeof(A == B), typeof(A + full(B)))
print(A + 1)
print(A * [1.0; 1.0])
print([1.0, 1.0] * A)
print(typeof(A * full(B)), typeof(full(A) * B))
print(isequal(full(A * B), full(A) * full(B)))
