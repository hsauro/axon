## Steady states of the feedback-inhibited pathway, and how S3 at steady state depends on Ki.

import antimony
import plot

model = antimony.load("""
    J0: -> S1;      v0 / (1 + (S3/Ki)^h)
    J1: S1 -> S2;   Vm1*S1/(Km1 + S1)
    J2: S2 -> S3;   Vm2*S2/(Km2 + S2)
    J3: S3 -> ;     k3*S3
    S1 = 0; S2 = 0; S3 = 0
    v0 = 10; Ki = 1; h = 4
    Vm1 = 12; Km1 = 2
    Vm2 = 15; Km2 = 1.5
    k3 = 2""")

s = antimony.steady_state(model)
println("status:", s.status, " iterations:", s.niters)
for i in 1:length(s.species)
  println(s.species[i], "=", format(s.y[i], 4))
end

# S3's steady state for 40 values of Ki.
kis = linspace(0.25, 4.0, 40)
s3 = zeros(40)
for k in 1:40
  model.parameters["Ki"] = kis[k]
  s3[k] = antimony.steady_state(model).y[3]
end
println("Ki = 4:", format(s3[end], 4))

plot.figure(width = 560, height = 300, title = "Steady state of S3")
plot.line(kis, s3, label = "S3")
plot.xlabel("Ki")
plot.ylabel("S3")
plot.save("../figures/pathway_steady.pdf")
