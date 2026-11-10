## Reaction models in Antimony: a feedback-inhibited pathway, read and simulated.
## The program from the manual's case study (Chapter 10, "Case study: reaction
## models"), which explains how the antimony module works.

import antimony
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

names = antimony.species_names(model)
println("species:", names)
println(antimony.stoichiometry(model))

# A time course from all species at zero.
sol = antimony.simulate(model, 10.0, points = 201)
for i in 1:length(names)
  println(names[i], "at t = 10:", format(sol.y[i, end], 4))
end

plot.new(width = 560, height = 320, title = "Feedback-inhibited pathway")
for i in 1:length(names)
  plot.line(sol.t, sol.y[i, :], label = names[i])
end
plot.xlabel("time")
plot.ylabel("concentration")

# A parameter scan: a weaker inhibitor (larger Ki) lets more S3 build up.
plot.new(width = 560, height = 320, title = "S3 for different Ki")
for Ki in {0.5, 1.0, 2.0, 4.0}
  model.parameters["Ki"] = Ki
  s = antimony.simulate(model, 10.0, points = 201)
  plot.line(s.t, s.y[3, :], label = "Ki = " + string(Ki))
end
plot.xlabel("time")
plot.ylabel("S3")
