# Robertson's chemical kinetics, a standard stiff test. Reference values at
# t = 40 (Hairer and Wanner): y1 = 0.7158270687, y2 = 9.185534764e-6,
# y3 = 0.2841637457. The three concentrations always sum to 1.
import ode
from testing import approx

rob = function(t, y)
  return [-0.04 * y[1] + 1e4 * y[2] * y[3];
           0.04 * y[1] - 1e4 * y[2] * y[3] - 3e7 * y[2] ^ 2;
           3e7 * y[2] ^ 2]
end
s = ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf", rtol = 1e-8, atol = 1e-12,
              t_eval = [40.0])
y = s.y[:, 1]
println(length(s.t), s.t[1])
println(approx(y[1], 0.7158270687, tol = 1e-6), approx(y[3], 0.2841637457, tol = 1e-6))
println(abs(y[2] - 9.185534764e-6) / 9.185534764e-6 < 1e-4)
println(abs(sum(y) - 1.0) < 1e-8)

# A solve inside a right-hand side, and many BDF solves in a row (CVODE's
# callbacks are shared, so these must not run out of trampolines).
inner = function(t, y)
  q = ode.solve(function(u, z) return -z end, 1.0, [0, 1], method = "bdf", rtol = 1e-10, atol = 1e-12)
  return -y * q.y[1, length(q.t)]
end
w = ode.solve(inner, 1.0, [0, 1], method = "bdf", rtol = 1e-10, atol = 1e-12)
println(approx(w.y[1, length(w.t)], exp(-exp(-1.0)), tol = 1e-6))
for k in 1:40
  q = ode.solve(function(t, y) return -y end, 1.0, [0, 1], method = "bdf")
end
println(q.status)
