from linalg import eig
from testing import approx_set
p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}
xs = [p.d/p.c; p.a/p.b]
J  = [p.a - p.b*xs[2],  -p.b*xs[1];
      p.c*xs[2],         p.c*xs[1] - p.d]
lambda = eig(J)          # purely imaginary pair: a centre
print(eltype(lambda), all(abs(real(lambda)) < 1e-12))
print(approx_set(lambda, [sqrt(1.5) * 1i; -sqrt(1.5) * 1i]))
import linalg
print(linalg.eig([1, 2; 3, 4]))
