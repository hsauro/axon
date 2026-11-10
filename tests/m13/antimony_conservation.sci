# antimony.conservation, the reduced steady state and the Jacobians.
import antimony
import linalg
from testing import approx, approx_set

# An enzyme, free (E) or bound (ES): E + ES is conserved.
src = """
  -> S; vin
  E + S -> ES; k1*E*S
  ES -> E + S; km1*ES
  ES -> E + P; k2*ES
  P -> ; kout*P
  vin = 1; k1 = 2; km1 = 1; k2 = 4; kout = 0.5
  E = 1; S = 0; ES = 0; P = 0
"""
m = antimony.load(src)
c = antimony.conservation(m)
N = antimony.stoichiometry(m)
println(c.independent, c.dependent, c.ind', c.dep')
println(c.L0)
println(c.gamma)
println(approx(N, c.link * c.Nr), approx(c.gamma * N, zeros(1, 5)), approx(c.Nr, N[c.ind, :]))

# Both methods give the same steady state; the reduced one solves for three
# species, the augmented one for four.
sr = antimony.steady_state(m)
sa = antimony.steady_state(m, method = "augmented")
exact = [5 * 0.25 / (2 * 0.75); 0.75; 0.25; 2.0]
println(approx(sr.y, exact, tol = 1e-9), approx(sa.y, exact, tol = 1e-9), sr.status)
println(approx(c.gamma * sr.y, c.gamma * antimony.initial(m)))

# The full Jacobian is singular; the reduced one has the same other
# eigenvalues, all negative: the steady state is stable.
J = antimony.jacobian(m, sr.y)
Jr = antimony.reduced_jacobian(m, sr.y)
println(size(J, 1), size(Jr, 1), abs(linalg.det(J)) < 1e-8, abs(linalg.det(Jr)) > 0.1)
ej = linalg.eig(J)
er = linalg.eig(Jr)
println(approx_set(ej, [er; 0.0], tol = 1e-6), max(er) < 0)
# The Jacobian by hand: v2 = k1 E S, so d(dS/dt)/dS = -k1 E.
println(approx(J[1, 1], -2 * 0.75, tol = 1e-8))

# Two separate cycles: two totals, A + B and C + D.
m2 = antimony.load("A -> B; k1*A; B -> A; k2*B; C -> D; k3*C; D -> C; k4*D; A = 10; C = 4; k1 = 1; k2 = 0.5; k3 = 2; k4 = 2")
c2 = antimony.conservation(m2)
println(c2.independent, c2.dependent)
println(c2.gamma)
println(approx(antimony.steady_state(m2).y, [10 / 3; 20 / 3; 2.0; 2.0], tol = 1e-9))

# No conserved totals: every species is independent and the link matrix is I.
m3 = antimony.load("-> S1; v0; S1 -> S2; k1*S1; S2 -> ; k2*S2; v0 = 2; k1 = 0.5; k2 = 4")
c3 = antimony.conservation(m3)
println(c3.independent, c3.dependent, size(c3.gamma, 1), approx(c3.link, eye(2)))
