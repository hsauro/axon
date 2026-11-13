## Metabolic control analysis: which steps control the flux?
##
## A pathway from a fixed source X0 branches at S2: one branch runs through
## S3 to the sink X1, the other straight to X2. S3 inhibits the first step,
## and the second step uses ATP, which J5 regenerates from ADP, so ATP + ADP
## is a conserved total. antimony.control finds the steady state and the
## control coefficients: the relative change in each flux and concentration
## when the activity of one step changes by a small relative amount. Each
## row of the flux control coefficients sums to 1 (the summation theorem)
## and each row of the concentration control coefficients to 0. The two
## matrices are drawn as 3D bar charts, coloured with coolwarm about 0; in
## the IDE, drag a chart to turn it.

import antimony
import fmt
import plot

m = antimony.load("""
  J0: $X0 -> S1; V0*X0/(K0 + X0)/(1 + S3/Ki)   // supply, inhibited by S3
  J1: S1 + ATP -> S2 + ADP; k1*S1*ATP          // uses ATP
  J2: S2 -> S3; Vm2*S2/(Km2 + S2)              // first branch
  J3: S3 -> $X1; k3*S3
  J4: S2 -> $X2; k4*S2                         // second branch
  J5: ADP -> ATP; k5*ADP                       // ATP regenerated
  X0 = 5; V0 = 10; K0 = 1; Ki = 2
  k1 = 1; Vm2 = 6; Km2 = 1; k3 = 2; k4 = 0.5; k5 = 3
  ATP = 3; ADP = 1
""")

c = antimony.control(m)
println("Steady state")
println(fmt.matrix(c.y, rows = c.species, cols = {"value"}, decimals = 4))
println()
println("Fluxes")
println(fmt.matrix(c.J, rows = c.reactions, cols = {"flux"}, decimals = 4))
println()
println("Flux control coefficients (row: the flux; column: the step changed)")
println(fmt.matrix(c.flux_control, rows = c.reactions, cols = c.reactions, decimals = 3))
println()
println("Concentration control coefficients (row: the species; column: the step)")
println(fmt.matrix(c.concentration_control, rows = c.species, cols = c.reactions,
                   decimals = 3))
println()
println("Row sums (summation theorems): flux " +
        fmt.matrix(sum(c.flux_control, 2)', decimals = 6) + ", concentration " +
        fmt.matrix(sum(c.concentration_control, 2)', decimals = 6))

plot.figure(width = 1100, height = 520, title = "Control coefficients of a branched pathway")
plot.subplot(1, 2, 1)
plot.bar3(c.reactions, c.reactions, c.flux_control, colormap = "coolwarm", clim = [-2, 2])
plot.title("Flux control")
plot.xlabel("step changed")
plot.ylabel("flux")
plot.subplot(1, 2, 2)
plot.bar3(c.reactions, c.species, c.concentration_control, colormap = "coolwarm",
          clim = [-2, 2])
plot.title("Concentration control")
plot.xlabel("step changed")
plot.ylabel("species")
plot.show()
