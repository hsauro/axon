# sol.at after a terminal event: the solution's last step ends early, at the
# event, and sol.at must still interpolate it with the step's own length.
# Until 2026-11-14 it used the shortened length, and values inside that step
# were wrong (6.048 instead of 5.934 at t = 9 here). y' = 1 - 0.1 y from 0
# has y = 10 (1 - e^(-0.1 t)); the event stops it at t = 10.
import ode
from testing import approx

f = function(t, y) return 1 - 0.1 * y end
g = function(t, y) return t - 10.0 end
for method in {"rk45", "bdf"}
  sol = ode.solve(f, 0.0, [0, 29], method = method, rtol = 1e-8, atol = 1e-10,
                  events = g, terminal = true)
  ok = true
  for t in {1.0, 5.0, 8.5, 9.0, 9.9, 10.0}
    ok = ok and approx(sol.at(t)[1], 10 * (1 - exp(-0.1 * t)), tol = 1e-6)
  end
  println(method, sol.status, approx(sol.t[end], 10.0, tol = 1e-12), ok)
end
