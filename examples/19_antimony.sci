## Reaction models in Antimony: a pathway read from text, then simulated.
## The antimony module reads reactions and rate laws, builds the differential
## equations from the stoichiometry, and solves them with ode.solve.

import antimony
import plot

# A linear pathway whose end product S3 inhibits the first step.
model = antimony.load("""
    J0: -> S1;      v0 / (1 + (S3/Ki)^h)    // inhibited supply
    J1: S1 -> S2;   Vm1*S1/(Km1 + S1)
    J2: S2 -> S3;   Vm2*S2/(Km2 + S2)
    J3: S3 -> ;     k3*S3                   # removal

    S1 = 0; S2 = 0; S3 = 0
    v0 = 10; Ki = 1; h = 4
    Vm1 = 12; Km1 = 2
    Vm2 = 15; Km2 = 1.5
    k3 = 2""")

names = antimony.species_names(model)
println("Species:", names)
println("Reactions:")
for r in model.reactions
  println(" ", r.name + ":", r.rate)
end
println("Stoichiometry matrix (one row per species, one column per reaction):")
println(antimony.stoichiometry(model))

# The time course from all species at zero.
sol = antimony.simulate(model, 10.0, points = 201)
plot.new(title = "Feedback-inhibited pathway", width = 640, height = 420)
for i in 1:length(names)
  plot.line(sol.t, sol.y[i, :], label = names[i])
end
plot.xlabel("time")
plot.ylabel("concentration")

# Changing a parameter: the model's parameters are an ordinary dictionary.
# A weaker inhibitor (larger Ki) lets more S3 accumulate.
plot.new(title = "S3 for different Ki", width = 640, height = 420)
for Ki in {0.5, 1.0, 2.0, 4.0}
  model.parameters["Ki"] = Ki
  s = antimony.simulate(model, 10.0, points = 201)
  plot.line(s.t, s.y[3, :], label = "Ki = " + string(Ki))
  println("Ki =", Ki, " S3 at t = 10:", format(s.y[3, end], 4))
end
plot.xlabel("time")
plot.ylabel("S3")
