# ode.solve with params: f and the event functions get it as a third argument.
import ode
from testing import approx

f = function(t, y, p) return -p.k * y end
g = function(t, y, p) return y[1] - p.level end

for m in {"rk45", "bdf"}
  p = {k: 0.5, level: 1.0}
  sol = ode.solve(f, 2.0, [0, 10], method = m, rtol = 1e-9, atol = 1e-12, params = p)
  println(m, approx(sol.y[1, :], 2 * exp(-0.5 * sol.t), tol = 1e-7))

  # A terminal event at y = level: 2 exp(-k t) = 1 at t = log(2) / k.
  se = ode.solve(f, 2.0, [0, 10], method = m, rtol = 1e-9, atol = 1e-12, params = p,
                 events = g, terminal = true)
  println(se.status, approx(se.t_events[1][1], log(2.0) / 0.5, tol = 1e-6))

  # Other params, same function: a different solution.
  s2 = ode.solve(f, 2.0, [0, 2], method = m, rtol = 1e-9, atol = 1e-12, params = {k: 1.0, level: 0.0})
  println(approx(s2.y[1, end], 2 * exp(-2.0), tol = 1e-7))
end

# A vector works as well, and without params f is called with two arguments.
h = function(t, y, p) return [-p[1] * y[1]; p[1] * y[1]] end
s3 = ode.solve(h, [1.0; 0.0], [0, 1], params = [2.0], rtol = 1e-9, atol = 1e-12)
println(approx(s3.y[:, end], [exp(-2.0); 1 - exp(-2.0)], tol = 1e-7))
try
  ode.solve(h, [1.0; 0.0], [0, 1])
catch err
  println(err.kind)
end
