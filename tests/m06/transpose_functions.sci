v = [1; 2; 3]
println(v')
A = [1, 2, 3; 4, 5, 6]
println(A')
Z = [1 + 2i, 3 - 1i]
println(Z')
println(adjoint(Z))
println(dot([1; 2; 3], [4; 5; 6]), dot([1i; 1], [1i; 1]))
println(sin([0.0, 0.0]))
println(exp([0; 0]))
println(abs([-1, 2; -3, 4]))
println(sqrt([4.0; -1.0]))
println(round([1.5, 2.5, -2.5]))
println(real([1 + 2i; 3]), imag([1 + 2i; 3]))
