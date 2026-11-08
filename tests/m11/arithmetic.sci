A = sparse([1, 2, 2], [1, 1, 2], [1.0, 2.0, 3.0])      # [1 0; 2 3]
B = sparse([1, 2], [2, 2], [4.0, -3.0])                # [0 4; 0 -3]

# Sparse with sparse stays sparse; a sum that cancels drops the entry.
println(A + B)
println(A - B)
println(A .* B)
println(A * B)

# A scalar with *, / and the elementwise forms.
println(2 * A)
println(A / 2)
println(typeof(A * 2), typeof(A ./ 2), typeof(2 .* A))
println(-B)

# Transposes, and powers by repeated multiplication.
println(A')
C = sparse([1, 2], [1, 2], [1i, 2.0])
println(adjoint(C))
println(A ^ 2)
println(typeof(A ^ 0), nnz(A ^ 0))

# Everything that fills in the zeros is dense.
println(typeof(A + 1), typeof(A ./ B), typeof(A == B), typeof(A + full(B)))
println(A + 1)
println(A * [1.0; 1.0])
println([1.0, 1.0] * A)
println(typeof(A * full(B)), typeof(full(A) * B))
println(isequal(full(A * B), full(A) * full(B)))
