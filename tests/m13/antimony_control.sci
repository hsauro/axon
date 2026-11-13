# Metabolic control analysis: rates, elasticities and control coefficients,
# against values worked out by hand, the summation and connectivity
# theorems, and the change in the steady state when one rate is perturbed.
import antimony
from testing import approx

# Two steps: v1 = k1 X0 - km1 S1, v2 = k2 S1; S1 = k1 X0 / (km1 + k2) = 4, J = 8.
m = antimony.load("""
  $X0 -> S1; k1*X0 - km1*S1
  S1 -> $X1; k2*S1
  X0 = 10; X1 = 0; k1 = 1; km1 = 0.5; k2 = 2""")
println(antimony.rates_text(m))
println(antimony.reaction_names(m), antimony.fluxes(m, 4.0)')

# Elasticities: dv/dS1 = [-km1; k2], scaled [-0.25; 1]. With respect to k1,
# km1, k2, X0, X1: v1 gives [X0, -S1, 0, k1, 0] and v2 [0, 0, S1, 0, 0].
println(approx(antimony.elasticities(m, [4.0]), reshape([-0.5; 2.0], 2, 1)))
println(approx(antimony.elasticities(m, [4.0], scaled = true), reshape([-0.25; 1.0], 2, 1)))
println(approx(antimony.parameter_elasticities(m, [4.0]),
               [10.0, -4.0, 0.0, 1.0, 0.0; 0.0, 0.0, 4.0, 0.0, 0.0]))
println(approx(antimony.parameter_elasticities(m, [4.0], scaled = true),
               [1.25, -0.25, 0.0, 1.25, 0.0; 0.0, 0.0, 1.0, 0.0, 0.0]))

# Control: CJ = [k2, km1] / (k2 + km1) = [0.8, 0.2] in both rows; Cs unscaled
# [1, -1] / (k2 + km1), scaled by J / S1 = 2.
c = antimony.control(m)
println(c.species, c.reactions, c.scaled, approx(c.y[1], 4.0), approx(c.J, [8.0; 8.0]))
println(approx(c.flux_control, [0.8, 0.2; 0.8, 0.2]), approx(c.concentration_control, [0.8, -0.8]))
println(approx(c.elasticities, reshape([-0.25; 1.0], 2, 1)))
u = antimony.control(m, scaled = false)
println(u.scaled, approx(u.flux_control, [0.8, 0.2; 0.8, 0.2]),
        approx(u.concentration_control, [0.4, -0.4]))
# At a given point instead of the steady state.
println(approx(antimony.control(m, y = [4.0]).flux_control, [0.8, 0.2; 0.8, 0.2]))

# Three reversible steps: S1 = S2 = 5, J = 5. By hand, CJ = [0.5, 0.25, 0.25]
# in every row; Cs [0.5, -0.25, -0.25] for S1 and [0.5, 0.25, -0.75] for S2
# (scaled the same, since J / S = 1).
chain = antimony.load("""
  $X0 -> S1; k1*X0 - km1*S1
  S1 -> S2; k2*S1 - km2*S2
  S2 -> $X1; k3*S2
  X0 = 10; k1 = 1; km1 = 1; k2 = 2; km2 = 1; k3 = 1""")
c = antimony.control(chain)
println(approx(c.y, [5.0; 5.0], tol = 1e-9), approx(c.J, [5.0; 5.0; 5.0], tol = 1e-9))
println(approx(c.flux_control, [0.5, 0.25, 0.25; 0.5, 0.25, 0.25; 0.5, 0.25, 0.25], tol = 1e-9))
println(approx(c.concentration_control, [0.5, -0.25, -0.25; 0.5, 0.25, -0.75], tol = 1e-9))

# A cycle with A + B = 10 conserved: A = 10/3, B = 20/3, J = 10/3. Through
# the link matrix, CJ = [1/3, 2/3] in both rows (J = T k1 k2 / (k1 + k2)),
# and Cs [-2/3, 2/3] for A and [1/3, -1/3] for B.
cyc = antimony.load("A -> B; k1*A; B -> A; k2*B; A = 10; k1 = 1; k2 = 0.5")
c = antimony.control(cyc)
println(approx(c.flux_control, [1.0, 2.0; 1.0, 2.0] / 3, tol = 1e-9),
        approx(c.concentration_control, [-2.0, 2.0; 1.0, -1.0] / 3, tol = 1e-9))

# A branched pathway with feedback inhibition and a conserved moiety (ATP +
# ADP). The scaled flux control coefficients of each flux sum to 1 and the
# concentration ones to 0; unscaled, CJ E L = 0 and Cs E L = -L (the
# connectivity theorems); and every coefficient agrees with the change in
# the steady state when one rate law is multiplied by 1 +- 1e-4.
m = antimony.load("""
  J0: $X0 -> S1; V0*X0/(K0 + X0)/(1 + S3/Ki)
  J1: S1 + ATP -> S2 + ADP; k1*S1*ATP
  J2: S2 -> S3; Vm2*S2/(Km2 + S2)
  J3: S3 -> $X1; k3*S3
  J4: S2 -> $X2; k4*S2
  J5: ADP -> ATP; k5*ADP
  X0 = 5; V0 = 10; K0 = 1; Ki = 2
  k1 = 1; Vm2 = 6; Km2 = 1; k3 = 2; k4 = 0.5; k5 = 3
  ATP = 3; ADP = 1""")
c = antimony.control(m)
println(c.species, c.reactions)
println(max(abs(sum(c.flux_control, 2) - 1)) < 1e-10,
        max(abs(sum(c.concentration_control, 2))) < 1e-10)
u = antimony.control(m, scaled = false)
E = antimony.elasticities(m, u.y)
L = antimony.conservation(m).link
println(max(abs(u.flux_control * E * L)) < 1e-12,
        max(abs(u.concentration_control * E * L + L)) < 1e-12)
d = 1e-4
w = log(1 + d) - log(1 - d)
n = length(c.J)
CJ = zeros(n, n)
CS = zeros(length(c.y), n)
for j in 1:n
  up = m
  up.reactions[j].rate = "(" + m.reactions[j].rate + ")*" + string(1 + d)
  down = m
  down.reactions[j].rate = "(" + m.reactions[j].rate + ")*" + string(1 - d)
  a = antimony.steady_state(up, guess = c.y)
  b = antimony.steady_state(down, guess = c.y)
  CJ[:, j] = (log(antimony.fluxes(up, a.y)) - log(antimony.fluxes(down, b.y))) / w
  CS[:, j] = (log(a.y) - log(b.y)) / w
end
println(approx(CJ, c.flux_control, tol = 1e-6), approx(CS, c.concentration_control, tol = 1e-6))

# Errors: the wrong number of values, and a point where the reduced Jacobian
# is singular (neither rate depends on S).
try
  antimony.control(cyc, y = [1.0; 2.0; 3.0])
catch err
  println(err.kind, err.message)
end
try
  antimony.elasticities(cyc, "x")
catch err
  println(err.kind, err.message)
end
flat = antimony.load("$X -> S; k; S -> ; k; k = 1")
try
  antimony.control(flat, y = [1.0])
catch err
  println(err.kind, err.message)
end
