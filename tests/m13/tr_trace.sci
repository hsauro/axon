# tr(A) is A' (no conjugation); trace(A) sums the diagonal of a square matrix.
A = [1, 2, 3; 4, 5, 6]
println(isequal(tr(A), A'), isequal(tr(tr(A)), A))
[m, n] = size(tr(A))
println(m, n, eltype(tr(A)))
println(isequal(tr([1.0; 2.0]), [1.0, 2.0]), tr(5), isequal(tr(1:3), [1, 2, 3]))
C = [1 + 2i, 3; 4, 5i]
println(isequal(tr(C), C'), isequal(tr(C), adjoint(C)), tr(C)[1, 2])

println(trace([1, 2; 3, 4]), trace([1.5, 0.0; 0.0, 2.5]), trace(C))
println(trace(7), trace(eye(4)), trace(speye(3)), trace([]))
println(trace(A * A'), trace(A' * A))
