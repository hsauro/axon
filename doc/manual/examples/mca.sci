## Elasticities and control coefficients of the feedback-inhibited pathway.

import antimony
import fmt
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

c = antimony.control(model)
println("Scaled elasticities")
println(fmt.matrix(c.elasticities, rows = c.reactions, cols = c.species,
                   decimals = 3))
println("Flux control coefficients, the same for each flux")
println(fmt.matrix(c.flux_control[1:1, :], rows = {"J"}, cols = c.reactions,
                   decimals = 3))
println("Concentration control coefficients")
println(fmt.matrix(c.concentration_control, rows = c.species,
                   cols = c.reactions, decimals = 3))

r = antimony.response(model)
println("Response of the flux to each parameter")
println(fmt.matrix(r.flux[1:1, :], rows = {"J"}, cols = r.parameters,
                   decimals = 3))

plot.figure(width = 520, height = 400, title = "Concentration control")
plot.bar3(c.reactions, c.species, c.concentration_control,
          colormap = "coolwarm", clim = [-1, 1])
plot.xlabel("step")
plot.ylabel("species")
plot.zlabel("C")
plot.save("../figures/mca.pdf")
