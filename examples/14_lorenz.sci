## The Lorenz attractor: a chaotic ODE solution drawn as a 3D curve.
## In the IDE, drag the plot to rotate it, wheel to zoom, right-drag to pan.

import ode
import plot

# dx/dt = sigma (y - x), dy/dt = x (rho - z) - y, dz/dt = x y - beta z
sigma = 10.0
rho = 28.0
beta = 8.0 / 3.0
lorenz = function(t, u)
  return [sigma * (u[2] - u[1]);
          u[1] * (rho - u[3]) - u[2];
          u[1] * u[2] - beta * u[3]]
end

# 40 time units, reported at 8000 evenly spaced times for a smooth curve.
sol = ode.solve(lorenz, [1.0; 1.0; 1.0], [0, 40], rtol = 1e-9, atol = 1e-12,
                t_eval = linspace(0.0, 40.0, 8000))
x = sol.y[1, :]
y = sol.y[2, :]
z = sol.y[3, :]
println("steps:", sol.nsteps, "final point:", format(x[end], 3), format(y[end], 3),
        format(z[end], 3))

# The two fixed points the trajectory circles around.
c = sqrt(beta * (rho - 1))
plot.figure(title = "Lorenz attractor", width = 720, height = 600)
plot.line3(x, y, z, label = "trajectory", width = 0.8)
plot.scatter3([c; -c], [c; -c], [rho - 1; rho - 1], label = "fixed points", color = "red",
              size = 9)
plot.xlabel("x")
plot.ylabel("y")
plot.zlabel("z")
plot.view(-50, 25)
plot.show()
