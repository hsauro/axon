## Steady states of reaction models, found with antimony.steady_state.
## A steady state is where the species stop changing. steady_state solves
## for it directly with Newton's method (nonlin.solve, SUNDIALS KINSOL)
## instead of simulating until nothing moves.

import antimony
import linalg
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

# The steady state, and a long simulation that ends in the same place.
s = antimony.steady_state(model)
sol = antimony.simulate(model, 20.0, points = 2)
println("status:", s.status, " Newton iterations:", s.niters)
for i in 1:length(s.species)
  println(s.species[i], "steady state:", format(s.y[i], 4), " simulated to t = 20:",
          format(sol.y[i, end], 4))
end

# How S3's steady state depends on the inhibition constant Ki: one solve per
# value, a few milliseconds each. The dots are simulations run to t = 30.
kis = linspace(0.25, 4.0, 60)
s3 = zeros(length(kis))
for k in 1:length(kis)
  model.parameters["Ki"] = kis[k]
  s3[k] = antimony.steady_state(model).y[3]
end
check = [0.5, 1.0, 2.0, 3.0, 4.0]
sim3 = zeros(length(check))
for k in 1:length(check)
  model.parameters["Ki"] = check[k]
  sim3[k] = antimony.simulate(model, 30.0, points = 2).y[3, end]
end

# A model with a conserved total: the enzyme E is free or bound in ES, so
# E + ES stays 1. conservation finds it; steady_state solves for the
# independent species S, ES and P, with E following from the total.
enzyme = antimony.load("""
    -> S; vin
    E + S -> ES; k1*E*S
    ES -> E + S; km1*ES
    ES -> E + P; k2*ES
    P -> ; kout*P
    vin = 1; k1 = 2; km1 = 1; k2 = 4; kout = 0.5
    E = 1; S = 0; ES = 0; P = 0""")
c = antimony.conservation(enzyme)
e = antimony.steady_state(enzyme)
println()
println("enzyme model:", e.species)
println("independent:", c.independent, " dependent:", c.dependent)
println("conservation law (gamma):", c.gamma)
println("steady state:", e.y')
println("E + ES =", e.y[2] + e.y[3])
# Stable: the eigenvalues of the reduced Jacobian are all negative.
println("eigenvalues of the reduced Jacobian:", linalg.eig(antimony.reduced_jacobian(enzyme, e.y))')

plot.new(width = 640, height = 400, title = "Steady state of S3 against Ki")
plot.line(kis, s3, label = "steady state")
plot.scatter(check, sim3, label = "simulated to t = 30")
plot.xlabel("Ki")
plot.ylabel("S3")
