## A stiff system with BDF, and an event that stops a simulation.

import ode
import plot

# Robertson's chemical kinetics: rates from 0.04 to 3e7, so it is stiff.
rob = function(t, y)
  return [-0.04*y[1] + 1e4*y[2]*y[3];
           0.04*y[1] - 1e4*y[2]*y[3] - 3e7*y[2]^2;
           3e7*y[2]^2]
end
s = ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf",
              rtol = 1e-8, atol = 1e-12, names = {"A", "B", "C"})
n = length(s.t)
println("BDF steps:", s.nsteps)
println("at t = 40:", format(s.y[1, n], 6), format(s.y[2, n], 10), format(s.y[3, n], 6))

# A ball thrown upwards at 12 m/s. The event function is the height;
# direction = -1 counts only falling crossings, and terminal stops there.
g = 9.81
ball = function(t, y) return [y[2]; -g] end
landed = function(t, y) return y[1] end
b = ode.solve(ball, [0.0; 12.0], [0, 10], events = landed, direction = -1,
              terminal = true, rtol = 1e-9, atol = 1e-12)
println("status:", b.status)
println("landed at t =", format(b.t_events[1][1], 6), " exact:", format(2 * 12.0 / g, 6))

plot.figure(width = 560, height = 300, title = "A ball thrown upwards")
plot.line(b.t, b.y[1, :], label = "height")
plot.xlabel("time (s)")
plot.ylabel("height (m)")
plot.save("../figures/ball.pdf")
