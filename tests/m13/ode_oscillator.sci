# y'' = -y as a system: y1 = cos t, y2 = -sin t; events where y1 crosses 0.
import ode
from testing import approx

osc = function(t, y) return [y[2]; -y[1]] end
pi = 3.141592653589793
for m in {"rk45", "bdf"}
  s = ode.solve(osc, [1.0; 0.0], [0, 10], method = m, rtol = 1e-10, atol = 1e-12,
                events = function(t, y) return y[1] end)
  print(m, approx(s.y[1, :], cos(s.t), tol = 1e-6), approx(s.y[2, :], -sin(s.t), tol = 1e-6))
  energy = s.y[1, :] .^ 2 + s.y[2, :] .^ 2
  print(max(abs(energy - 1.0)) < 1e-6)
  print(length(s.t_events[1]), approx(s.t_events[1], [pi / 2; 3 * pi / 2; 5 * pi / 2], tol = 1e-6))
  print(approx(s.y_events[1][2, :], [-1.0; 1.0; -1.0], tol = 1e-6))
end

# Only rising crossings.
up = ode.solve(osc, [1.0; 0.0], [0, 10], events = function(t, y) return y[1] end,
               direction = 1, rtol = 1e-10, atol = 1e-12)
print(length(up.t_events[1]), approx(up.t_events[1][1], 3 * pi / 2, tol = 1e-6))

# A terminal event ends the solution at the event.
for m in {"rk45", "bdf"}
  h = ode.solve(osc, [1.0; 0.0], [0, 10], method = m, events = function(t, y) return y[1] end,
                terminal = true, rtol = 1e-10, atol = 1e-12)
  n = length(h.t)
  print(h.status, approx(h.t[n], pi / 2, tol = 1e-6), abs(h.y[1, n]) < 1e-6)
end

# Two events, only the second terminal. y2 starts at exactly 0, which does
# not count; cos t + 1/2 reaches 0 at 2 pi / 3, before y2's first crossing.
two = ode.solve(osc, [1.0; 0.0], [0, 10],
                events = {function(t, y) return y[2] end, function(t, y) return y[1] + 0.5 end},
                terminal = {false, true}, rtol = 1e-10, atol = 1e-12)
print(length(two.t_events[1]), approx(two.t_events[2][1], 2 * pi / 3, tol = 1e-6), two.status)
