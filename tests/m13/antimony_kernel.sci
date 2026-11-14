# antimony.kernel, and conservation and kernel of a stoichiometry matrix.
import antimony
import linalg
from testing import approx

# A branch: J1 = J2 + J3. Two fluxes are independent, and the kernel
# matrix gives the steady-state fluxes from them.
m = antimony.load("""
  J1: -> S; v0
  J2: S -> ; k1*S
  J3: S -> ; k2*S
  v0 = 3; k1 = 1; k2 = 2
""")
k = antimony.kernel(m)
N = antimony.stoichiometry(m)
println(length(k.independent), length(k.dependent), size(k.K, 1), size(k.K, 2))
println(approx(N * k.K, zeros(1, 2)), approx(k.K[k.ind, :], eye(2)), approx(k.K[k.dep, :], k.K0))
println(isequal(sort([k.ind; k.dep]), [1; 2; 3]), isequal(k.ind, sort(k.ind)))
J = antimony.fluxes(m, antimony.steady_state(m).y)
println(approx(J, [3.0; 1.0; 2.0], tol = 1e-9), approx(k.K * J[k.ind], J, tol = 1e-9))

# A chain: every flux is the same, whichever is chosen as independent.
m2 = antimony.load("J1: -> S1; v0; J2: S1 -> S2; k1*S1; J3: S2 -> ; k2*S2; v0 = 2; k1 = 0.5; k2 = 4")
k2 = antimony.kernel(m2)
println(length(k2.independent), approx(k2.K[:, 1], [1.0; 1.0; 1.0]))

# An enzyme, free (E) or bound (ES): E + ES is conserved, and the binding
# step J1 and its reverse J2 form a cycle, so two fluxes are independent.
m3 = antimony.load("""
  J0: -> S; vin
  J1: E + S -> ES; k1*E*S
  J2: ES -> E + S; km1*ES
  J3: ES -> E + P; k2*ES
  J4: P -> ; kout*P
  vin = 1; k1 = 2; km1 = 1; k2 = 4; kout = 0.5
  E = 1; S = 0; ES = 0; P = 0
""")
k3 = antimony.kernel(m3)
N3 = antimony.stoichiometry(m3)
println(size(k3.K, 2), approx(N3 * k3.K, zeros(4, 2)))
J3 = antimony.fluxes(m3, antimony.steady_state(m3).y)
println(approx(k3.K * J3[k3.ind], J3, tol = 1e-9))

# One reaction, A -> B: no flux but 0 balances it.
k4 = antimony.kernel(antimony.load("J1: A -> B; k*A; k = 1"))
println(k4.independent, k4.dependent, size(k4.K, 1), size(k4.K, 2))

# Matrices: species named S1, S2, ... and reactions J1, J2, ... Here
# S2 = (S3 - S1) / 2, and S3 and then S1 have the largest rows.
c = antimony.conservation([1, 0; 0, 1; 1, 2])
println(c.independent, c.dependent, approx(c.L0, [-0.5, 0.5]))
# The same matrix's transpose as a stoichiometry matrix: J2's flux is
# independent, and J1 = J2 / 2, J3 = -J2 / 2.
k5 = antimony.kernel([1, 0, 1; 0, 1, 2])
println(k5.independent, k5.dependent, approx(k5.K[:, 1], [0.5; 1.0; -0.5]))

# A <-> B <-> C: A + B + C is conserved, and each pair of reactions is a
# cycle (J1 = J2, J3 = J4).
N6 = [-1, 1, 0, 0; 1, -1, -1, 1; 0, 0, 1, -1]
c6 = antimony.conservation(N6)
k6 = antimony.kernel(N6)
println(length(c6.dependent), approx(c6.gamma, [1.0, 1.0, 1.0]), approx(N6, c6.link * c6.Nr))
println(approx(k6.K, [1.0, 0.0; 1.0, 0.0; 0.0, 1.0; 0.0, 1.0]))

# A vector is one reaction; with no rows every reaction is independent.
println(antimony.kernel([-1; 1]).dependent, antimony.kernel(zeros(0, 2)).independent)
