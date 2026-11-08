import ode
import plot
from linalg import eig

p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}

f = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2];
          p.c*y[1]*y[2] - p.d*y[2]]
end

sol = ode.solve(f, [10.0; 5.0], [0, 50], method="rk45", rtol=1e-8)

# Coexistence fixed point and its Jacobian
xs = [p.d/p.c; p.a/p.b]
J  = [p.a - p.b*xs[2],  -p.b*xs[1];
      p.c*xs[2],         p.c*xs[1] - p.d]
lambda = eig(J)          # purely imaginary pair: a centre

plot.line(sol.t, sol.y[1, :], label="prey")
plot.line(sol.t, sol.y[2, :], label="predator")

# ---- checks (not part of the white paper's example) ----
from testing import approx, approx_set
println(sol.status, sol.t[length(sol.t)], size(sol.y, 1))
# J = [0, -2; 0.75, 0], so the eigenvalues are +-i sqrt(1.5).
println(typeof(lambda), eltype(lambda))
println(approx(real(lambda), [0.0; 0.0]), approx_set(imag(lambda), [sqrt(1.5); -sqrt(1.5)]))
# The orbit keeps V = c x - d log x + b y - a log y constant.
V = function(y) return p.c*y[1] - p.d*log(y[1]) + p.b*y[2] - p.a*log(y[2]) end
drift = 0.0
for k in 1:length(sol.t)
  drift = max(drift, abs(V(sol.y[:, k]) - V(sol.y[:, 1])))
end
println(drift < 1e-6)
fig = plot.gcf()
println(length(fig.series), fig.series[1].label, fig.series[2].label, fig.series[1].color)
