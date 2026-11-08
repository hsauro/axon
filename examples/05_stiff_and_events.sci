## Stiff equations with BDF (CVODE), and events that stop a simulation.

import ode
import plot

# Robertson's chemical kinetics: stiff, so method = "bdf".
rob = function(t, y)
  return [-0.04*y[1] + 1e4*y[2]*y[3];
           0.04*y[1] - 1e4*y[2]*y[3] - 3e7*y[2]^2;
           3e7*y[2]^2]
end
s = ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf", rtol = 1e-8, atol = 1e-12,
              names = {"A", "B", "C"})
n = length(s.t)
println("BDF took", s.nsteps, "steps; at t = 40:", s.y[1, n], s.y[2, n], s.y[3, n])

# A ball thrown upwards; a terminal event stops it when it lands.
g = 9.81
ball = function(t, y) return [y[2]; -g] end
landed = function(t, y) return y[1] end
b = ode.solve(ball, [0.0; 12.0], [0, 10], events = landed, direction = -1, terminal = true,
              rtol = 1e-9, atol = 1e-12)
println("status:", b.status, " landed at t =", b.t_events[1][1], " (exact:", 2 * 12.0 / g, ")")

plot.figure(title = "Ball height")
plot.line(b.t, b.y[1, :], label = "height")
plot.xlabel("time (s)")
plot.ylabel("height (m)")
plot.show()
