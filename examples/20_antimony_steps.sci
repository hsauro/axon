## Changing a parameter during a simulation: the Antimony pathway advanced in
## steps with ode.advance, with the inhibition weakened halfway through.
## The solver keeps its state between steps and restarts only at the change.

import antimony
import ode
import plot

model = antimony.load("""
    J0: -> S1;      v0 / (1 + (S3/Ki)^h)    // supply, inhibited by S3
    J1: S1 -> S2;   Vm1*S1/(Km1 + S1)
    J2: S2 -> S3;   Vm2*S2/(Km2 + S2)
    J3: S3 -> ;     k3*S3                   # removal

    S1 = 0; S2 = 0; S3 = 0
    v0 = 10; Ki = 1; h = 4
    Vm1 = 12; Km1 = 2
    Vm2 = 15; Km2 = 1.5
    k3 = 2""")

# The right-hand side f(t, y, p), the starting state and the parameters.
f = antimony.rhs(model)
names = antimony.species_names(model)
y = antimony.initial(model)
p = antimony.parameter_values(model)

# Where Ki is in the parameter vector p.
ki = 0
pnames = keys(model.parameters)
for i in 1:length(pnames)
  if pnames[i] == "Ki"
    ki = i
  end
end

# 400 steps of 0.05 to t = 20; Ki goes from 1 to 4 at t = 10.
s = ode.integrator(f, method = "bdf")
n = 400
half = div(n, 2)
dt = 0.05
times = linspace(0.0, n * dt, n + 1)
Y = zeros(length(names), n + 1)
Y[:, 1] = y
for k in 1:n
  if k == half + 1
    p[ki] = 4.0
    println("t = " + string(times[k]) + ": Ki raised to", p[ki])
  end
  y = ode.advance(s, times[k], y, times[k + 1], params = p)
  Y[:, k + 1] = y
end

for i in 1:length(names)
  println(names[i], "at t = 10:", format(Y[i, half + 1], 4), "at t = 20:", format(Y[i, end], 4))
end

plot.new(width = 640, height = 400, title = "Ki raised from 1 to 4 at t = 10")
for i in 1:length(names)
  plot.line(times, Y[i, :], label = names[i])
end
plot.line([10.0, 10.0], [0.0, 4.0], color = "gray", style = "--", label = "Ki changed")
plot.xlabel("time")
plot.ylabel("concentration")
