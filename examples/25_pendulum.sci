## An animated pendulum (Rosetta Code, "Animate a pendulum"): the motion
## is solved with an ODE integrator that keeps its state from frame to frame,
## and each frame is drawn with the draw module and shown with draw.frame,
## which replaces the picture in the plot pane 30 times a second.

import draw
import ode

g = 9.81            # gravity, m/s^2
L = 1.0             # length of the rod, m

# The pendulum: y = [angle from the vertical, angular velocity];
# angle'' = -(g / L) sin(angle).
function swing(t, y)
  return [y[2]; -g / L * sin(y[1])]
end

s = ode.integrator(swing, rtol = 1e-9)
y = [pi / 3; 0.0]                 # let go at 60 degrees, at rest
fps = 30
t = 0.0

for k in 1:20 * fps               # twenty seconds
  y = ode.advance(s, t, y, t + 1 / fps)
  t = t + 1 / fps

  # The bob, with the pivot at (0, 0) and y pointing up.
  bx = L * sin(y[1])
  by = -L * cos(y[1])
  draw.canvas(width = 400, height = 360, view = [-1.25, 1.25, -1.5, 0.75])
  draw.rect(-0.4, 0, 0.8, 0.08, fill = "gray", color = "none")    # the support
  draw.line(0, 0, bx, by, width = 2)                               # the rod
  draw.circle(0, 0, 0.03, fill = "black")                          # the pivot
  draw.circle(bx, by, 0.12, fill = "orange")                       # the bob
  draw.text(-1.15, -1.4, "t = " + format(t, 1) + " s   angle = " +
            format(y[1] * 180 / pi, 1) + " degrees", size = 11)
  draw.frame(fps = fps)
end

# The energy per unit mass stays what it was at the start.
energy = 0.5 * (L * y[2]) ^ 2 - g * L * cos(y[1])
println("energy at the start:", format(-g * L * cos(pi / 3), 6), " at the end:", format(energy, 6))
