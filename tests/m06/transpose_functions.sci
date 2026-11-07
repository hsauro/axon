v = [1; 2; 3]
print(v')
A = [1, 2, 3; 4, 5, 6]
print(A')
Z = [1 + 2i, 3 - 1i]
print(Z')
print(adjoint(Z))
print(dot([1; 2; 3], [4; 5; 6]), dot([1i; 1], [1i; 1]))
print(sin([0.0, 0.0]))
print(exp([0; 0]))
print(abs([-1, 2; -3, 4]))
print(sqrt([4.0; -1.0]))
print(round([1.5, 2.5, -2.5]))
print(real([1 + 2i; 3]), imag([1 + 2i; 3]))
