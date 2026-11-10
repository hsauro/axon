# antimony.steady_state: where dy/dt = 0, with conserved totals kept.
import antimony
from testing import approx

# A + B is conserved and stays 10: A = 10 k2 / (k1 + k2).
m = antimony.load("A -> B; k1*A; B -> A; k2*B; A = 10; k1 = 1; k2 = 0.5")
s = antimony.steady_state(m)
println(s.species, s.status, approx(s.y, [10 / 3; 20 / 3], tol = 1e-9))

# No conserved total: a chain fed at v0. S1 = v0 / k1, S2 = v0 / k2.
m = antimony.load("-> S1; v0; S1 -> S2; k1*S1; S2 -> ; k2*S2; v0 = 2; k1 = 0.5; k2 = 4")
s = antimony.steady_state(m)
println(approx(s.y, [4.0; 0.5], tol = 1e-9))

# An enzyme (E + ES conserved) with substrate fed in and product removed:
# ES = vin / k2, E = Et - ES, S = (km1 + k2) ES / (k1 E), P = vin / kout.
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
s = antimony.steady_state(m)
println(s.species, approx(s.y, [5 * 0.25 / (2 * 0.75); 0.75; 0.25; 2.0], tol = 1e-9))
# A long simulation ends there too.
sol = antimony.simulate(m, 200.0, method = "bdf", points = 2, rtol = 1e-10, atol = 1e-12)
println(approx(sol.y[:, end], s.y, tol = 1e-7))
# Another guess finds the same state; the totals come from the model's initial values.
s2 = antimony.steady_state(m, guess = [1.0; 0.5; 0.5; 1.0])
println(approx(s2.y, s.y, tol = 1e-9))
# A parameter changed in the model moves the steady state: P = vin / kout.
m.parameters["kout"] = 0.25
println(approx(antimony.steady_state(m).y[4], 4.0, tol = 1e-9))
