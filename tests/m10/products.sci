from testing import approx
A = [1.5, 2.0; -1.0, 0.5]
B = [2.0, 1.0, 0.0; 1.0, -1.0, 3.0]
print(A * B)
print(approx(A * B, [5.0, -0.5, 6.0; -1.5, -1.5, 1.5]))
v = [1.0; 2.0]
print(A * v, v' * v)
Z = [1 + 1i, 2; 0, 1 - 1i]
print(Z * Z)
print(approx(Z * [1.0; 1.0], [3.0 + 1i; 1.0 - 1i]))
print([1, 2; 3, 4] * [5, 6; 7, 8], typeof([1, 2] * [3; 4]))
C = rand(40, 30)
D = rand(30, 20)
P = C * D
ok = true
for i in 1:40
  for j in 1:20
    if abs(P[i, j] - sum(C[i, :] .* D[:, j])) > 1e-12 ok = false end
  end
end
print(ok, size(P, 1), size(P, 2))
