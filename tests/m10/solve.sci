from testing import approx
A = [4.0, -2.0, 1.0; -2.0, 4.0, -2.0; 1.0, -2.0, 4.0]
b = [11.0; -16.0; 17.0]
x = A \ b
println(typeof(x), approx(x, [1.0; -2.0; 3.0]))
X = A \ [b, 2 * b]
println(typeof(X), approx(X, [1.0, 2.0; -2.0, -4.0; 3.0, 6.0]))
println(approx([1, 2; 3, 4] \ [5; 6], [-4.0; 4.5]))
Ac = [2 + 1i, 1; 1, 3 - 1i]
xc = Ac \ [1; 1i]
println(eltype(xc), approx(Ac * xc, [1.0 + 0i; 1i]))
# Least squares: the line through (1,1), (2,2), (3,2).
coef = [1.0, 1.0; 1.0, 2.0; 1.0, 3.0] \ [1.0; 2.0; 2.0]
println(approx(coef, [2.0 / 3.0; 0.5]))
# Underdetermined: the minimum-norm solution.
println(approx([1.0, 1.0] \ [2.0], [1.0; 1.0]))
# Right division.
println(approx([1.0, 2.0] / [2.0, 0.0; 1.0, 1.0], [-0.5, 2.0]))
println(approx(A / A, eye(3)))
