## The Lorenz attractor: an ODE solution drawn as a 3D curve.

import ode
import plot

sigma = 10.0
rho = 28.0
beta = 8.0 / 3.0
lorenz = function(t, u)
  return [sigma * (u[2] - u[1]);
          u[1] * (rho - u[3]) - u[2];
          u[1] * u[2] - beta * u[3]]
end

sol = ode.solve(lorenz, [1.0; 1.0; 1.0], [0, 30], rtol = 1e-9, atol = 1e-12,
                t_eval = linspace(0.0, 30.0, 6000))
x = sol.y[1, :]
y = sol.y[2, :]
z = sol.y[3, :]

# The two fixed points the trajectory circles around.
c = sqrt(beta * (rho - 1))
plot.figure(width = 520, height = 420, title = "Lorenz attractor")
plot.line3(x, y, z, label = "trajectory", width = 0.6)
plot.scatter3([c; -c], [c; -c], [rho - 1; rho - 1], label = "fixed points",
              color = "red", size = 8)
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")
plot.view(-50, 25)
plot.save("../figures/lorenz.pdf")
