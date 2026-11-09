## Subplots: a damped oscillator seen four ways in one figure.

import ode
import plot

w = 2.0
zeta = 0.15
osc = function(t, u)
  return [u[2]; -2 * zeta * w * u[2] - w * w * u[1]]
end
sol = ode.solve(osc, [1.0; 0.0], [0, 15], t_eval = linspace(0.0, 15.0, 600))
t = sol.t
x = sol.y[1, :]
v = sol.y[2, :]
energy = 0.5 * v .* v + 0.5 * w * w * x .* x

plot.figure(width = 760, height = 520, title = "Damped oscillator")

plot.subplot(2, 2, 1)
plot.line(t, x, label = "x")
plot.line(t, v, label = "x'", style = "--")
plot.title("Position and velocity")

plot.subplot(2, 2, 2)
plot.line(x, v)
plot.title("Phase plane")
plot.xlabel("x")
plot.ylabel("x'")

plot.subplot(2, 2, 3)
plot.line(t, energy)
plot.title("Energy")
plot.xlabel("t")

# The local maxima of x.
peaks = zeros(0)
for k in 2:length(x) - 1
  if x[k] > x[k - 1] and x[k] > x[k + 1]
    peaks = [peaks; x[k]]
  end
end
plot.subplot(2, 2, 4)
plot.bar(peaks)
plot.title("Height of each peak")
plot.save("../figures/subplots.pdf")
