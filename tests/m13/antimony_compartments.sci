# Compartments, species declarations, assignment rules and ln, in models
# whose steady states and control coefficients are worked out by hand.
import antimony
from testing import approx

# Rate laws give amounts per unit time, so a concentration changes by the
# amount over its compartment's size. The rule b is computed before a, which
# uses it; ln is the natural logarithm.
m = antimony.load("""
  compartment inside, outside
  species S in inside, $X in outside, P in outside
  a := 2*b
  b := ln(X)
  J1: $X -> S; k1*exp(a/2)      // = k1 X
  J2: S -> P; inside*k2*S
  J3: P -> ; outside*k3*P
  inside = 2; outside = 10
  k1 = 1; k2 = 0.5; k3 = 0.2; X = 4
""")
println(antimony.species_names(m), antimony.boundary_names(m), keys(m.rules))
println(m.compartments, m.species_in)
println(antimony.parameter_names(m), antimony.volumes(m)')
println(antimony.rhs_text(m))

# dS/dt = (k1 X - inside k2 S) / inside = (4 - S) / 2, so S = 4 (1 - exp(-t/2))
# from 0, and S = 4 at steady state; inside k2 S = outside k3 P gives P = 2.
ss = antimony.steady_state(m)
println(ss.status, approx(ss.y, [4.0; 2.0], tol = 1e-9))
sol = antimony.simulate(m, 2.0, points = 5, rtol = 1e-10, atol = 1e-12)
println(approx(sol.y[1, :], 4 * (1 - exp(-sol.t / 2)), tol = 1e-8))
println(approx(antimony.fluxes(m, ss.y), [4.0; 4.0; 4.0], tol = 1e-9))

# The supply J1 does not depend on S, so it has all the flux control; S
# follows J1 / J2 and P follows J1 / J3, whatever the compartments' sizes.
c = antimony.control(m)
println(approx(c.flux_control, [1.0, 0.0, 0.0; 1.0, 0.0, 0.0; 1.0, 0.0, 0.0], tol = 1e-9),
        approx(c.concentration_control, [1.0, -1.0, 0.0; 1.0, 0.0, -1.0], tol = 1e-9))

# A conserved amount across compartments: A in a compartment of size 2 and B
# in one of size 10 (sizes given in the declaration), so 2 A + 10 B stays 12.
# At steady state c1 kf A = c2 kr B, A = 2.5 B, so B = 0.8 and A = 2, by
# either method.
t = antimony.load("""
  compartment c1 = 2, c2 = 10
  species A in c1, B in c2
  A -> B; c1*kf*A - c2*kr*B
  A = 6; kf = 1; kr = 0.5
""")
println(t.compartments, antimony.conservation(t).dependent)
for method in {"reduced", "augmented"}
  s = antimony.steady_state(t, method = method)
  println(method, s.status, approx(s.y, [2.0; 0.8], tol = 1e-9))
end

# Errors.
try
  antimony.load("A -> B; k*A; A := 2; k = 1")
catch err
  println(err.kind, err.message)
end
try
  antimony.rhs(antimony.load("x := y + 1; y := 2*x; -> S; x"))
catch err
  println(err.kind, err.message)
end
try
  antimony.load("species A in")
catch err
  println(err.message)
end
