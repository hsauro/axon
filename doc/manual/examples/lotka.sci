## Lotka-Volterra predator and prey, solved with RK45 and plotted.

import ode
import plot

# Parameters as a record: p.a, p.b, ...
p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}

# The right-hand side: y[1] is the prey, y[2] the predator.
f = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2];
          p.c*y[1]*y[2] - p.d*y[2]]
end

sol = ode.solve(f, [10.0; 5.0], [0, 30], rtol = 1e-8, names = {"prey", "predator"})
n = length(sol.t)
println("status:", sol.status, " steps:", sol.nsteps)
println("prey at t = 30:", format(sol.y[1, n], 3))

# The dense output gives the state at any time in the solved range.
println("state at t = 12.5:", sol.at(12.5))

plot.figure(width = 560, height = 320, title = "Lotka-Volterra")
plot.line(sol.t, sol.y[1, :], label = "prey")
plot.line(sol.t, sol.y[2, :], label = "predator", style = "--")
plot.xlabel("time")
plot.ylabel("population")
plot.save("../figures/lotka.pdf")
