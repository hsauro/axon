## Lotka-Volterra predator and prey: an ODE solved with RK45 and plotted.
## The white paper's worked example, with plot.show() to display the figure.

import ode
import plot
from linalg import eig

p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}

f = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2];
          p.c*y[1]*y[2] - p.d*y[2]]
end

sol = ode.solve(f, [10.0; 5.0], [0, 50], method="rk45", rtol=1e-8)
print("steps:", sol.nsteps, " final state:", sol.y[1, length(sol.t)], sol.y[2, length(sol.t)])

# Coexistence fixed point and its Jacobian: a purely imaginary pair (a centre).
xs = [p.d/p.c; p.a/p.b]
J  = [p.a - p.b*xs[2],  -p.b*xs[1];
      p.c*xs[2],         p.c*xs[1] - p.d]
print("eigenvalues of the Jacobian:")
print(eig(J))

plot.figure(title = "Lotka-Volterra")
plot.line(sol.t, sol.y[1, :], label="prey")
plot.line(sol.t, sol.y[2, :], label="predator")
plot.xlabel("time")
plot.ylabel("population")
plot.show()
