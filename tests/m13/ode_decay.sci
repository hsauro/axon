# y' = -y/2, y(0) = 2: y = 2 exp(-t/2), with both methods.
import ode
from testing import approx

f = function(t, y) return -0.5 * y end
for m in {"rk45", "bdf"}
  sol = ode.solve(f, 2.0, [0, 10], method = m, rtol = 1e-8, atol = 1e-10)
  n = length(sol.t)
  print(m, sol.status, sol.method, sol.names, typeof(sol.y))
  print(sol.t[1], sol.t[n], sol.y[1, 1])
  print(approx(sol.y[1, :], 2 * exp(-0.5 * sol.t), tol = 1e-6))
  print(approx(sol.at(3.3)[1], 2 * exp(-1.65), tol = 1e-6))
  print(sol.nsteps > 0, sol.nfev > sol.nsteps)
end

# Requested output times.
te = linspace(0.0, 10.0, 6)
s2 = ode.solve(f, 2.0, [0, 10], t_eval = te, rtol = 1e-8)
print(length(s2.t), s2.t[2], s2.t[6], approx(s2.y[1, :], 2 * exp(-0.5 * te), tol = 1e-6))

# Backwards in time.
b = ode.solve(f, 2 * exp(-5.0), [10, 0], rtol = 1e-9)
print(b.t[length(b.t)], approx(b.y[1, length(b.t)], 2.0, tol = 1e-6))

# Several components, names, and dense output at several times.
g = ode.solve(function(t, y) return [1.0; 2.0 * t] end, [0.0; 0.0], [0, 2], names = {"a", "b"})
print(g.names, approx(g.at(2.0), [2.0; 4.0], tol = 1e-8))
print(approx(g.at([0.5; 1.0]), [0.5, 1.0; 0.25, 1.0], tol = 1e-8))
