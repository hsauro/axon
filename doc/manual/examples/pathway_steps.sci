## The pathway advanced in steps, with the inhibition weakened halfway.

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

sim = antimony.simulator(model)
t = [sim.t]
s3 = [antimony.value(sim, "S3")]
for k in 1:200
  if k == 101
    sim = antimony.set(sim, "Ki", 4.0)       # at t = 10
  end
  sim = antimony.step(sim, 0.1)
  t = append(t, sim.t)
  s3 = append(s3, antimony.value(sim, "S3"))
end
println("t =", format(sim.t, 2), "S3 =", format(antimony.value(sim, "S3"), 4),
        "Ki =", antimony.value(sim, "Ki"))

plot.figure(width = 560, height = 300, title = "Ki raised from 1 to 4 at t = 10")
plot.line(t, s3, label = "S3")
plot.xlabel("time")
plot.ylabel("S3")
plot.save("../figures/pathway_steps.pdf")
