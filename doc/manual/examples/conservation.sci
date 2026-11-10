## Conservation analysis of an enzyme model, its steady state found two
## ways, and the stability of that state.

import antimony
import linalg

model = antimony.load("""
    J0: -> S;          vin
    J1: E + S -> ES;   k1*E*S
    J2: ES -> E + S;   km1*ES
    J3: ES -> E + P;   k2*ES
    J4: P -> ;         kout*P
    vin = 1; k1 = 2; km1 = 1; k2 = 4; kout = 0.5
    E = 1; S = 0; ES = 0; P = 0""")

# The values of a vector or one-row matrix, on one line, d decimals each.
function row(v, d)
  parts = {}
  for x in v
    parts = append(parts, format(x, d))
  end
  return join(parts, "  ")
end

c = antimony.conservation(model)
println("species:", antimony.species_names(model))
println("independent:", c.independent, " dependent:", c.dependent)
println("L0:", row(c.L0, 1), "   gamma:", row(c.gamma, 1))
println("total:", c.gamma * antimony.initial(model))

# Both methods: three unknowns (S, ES, P), or all four.
for method in {"reduced", "augmented"}
  s = antimony.steady_state(model, method = method)
  println(method + ":", row(s.y, 4), "  iterations:", s.niters)
end

# Stability: the eigenvalues of the full and of the reduced Jacobian.
s = antimony.steady_state(model)
println("J: ", row(sort(linalg.eig(antimony.jacobian(model, s.y))), 4))
println("Jr:", row(sort(linalg.eig(antimony.reduced_jacobian(model, s.y))), 4))
