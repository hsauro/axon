# Boundary species: "$X" fixes X. It has no row in N; its value follows the
# parameters in p, so rate laws, steady states and simulators read it.
import antimony
from testing import approx

m = antimony.load("""
  $X0 -> S1; k1*X0 - km1*S1
  S1 -> $X1; k2*S1
  X0 = 10; X1 = 0
  k1 = 1; km1 = 0.5; k2 = 2""")
println(antimony.species_names(m), antimony.boundary_names(m))
println(antimony.parameter_names(m))
println(m.boundary, m.parameters)
println(m.reactions[1].reactants, m.reactions[2].products)
println(antimony.stoichiometry(m))
println(antimony.parameter_values(m)')
println(antimony.rhs_text(m))

# S1 = k1 X0 / (km1 + k2) = 4 at steady state, reached as 4 (1 - exp(-2.5 t)).
ss = antimony.steady_state(m)
println(ss.status, approx(ss.y[1], 4.0, tol = 1e-9))
sol = antimony.simulate(m, 2.0, points = 5, rtol = 1e-10, atol = 1e-12)
println(approx(sol.y[1, :], 4 * (1 - exp(-2.5 * sol.t)), tol = 1e-8))
c = antimony.conservation(m)
println(c.independent, c.dependent)

# A boundary value changed in the model, or in a simulator.
m.boundary["X0"] = 20
println(approx(antimony.steady_state(m).y[1], 8.0, tol = 1e-9))
sim = antimony.simulator(m)
println(sim.parameters)
sim = antimony.set(sim, "X0", 5)
println(antimony.value(sim, "X0"), antimony.value(sim, "X1"))

# "$" once makes a name a boundary species everywhere; one never assigned
# is 0; "$" may also mark an assignment.
n = antimony.load("$A -> B; k*A; A -> C; k*A; $D = 3; k = 1; A = 2")
println(antimony.species_names(n), antimony.boundary_names(n), n.boundary)
println(antimony.stoichiometry(n))
println(antimony.parameter_values(antimony.load("$X -> Y; k*X; k = 2"))')

# Models without "$" have no boundary species.
println(antimony.load("A -> B; k*A; k = 1").boundary)

try
  antimony.load("$ -> A; 1")
catch err
  println(err.message)
end
