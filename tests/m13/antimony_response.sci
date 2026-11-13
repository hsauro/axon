# antimony.response: response coefficients of the steady state to the
# parameters and boundary species, by hand and against perturbation.
import antimony
from testing import approx

# Two steps: J = k1 k2 X0 / (km1 + k2) = 8 and S1 = k1 X0 / (km1 + k2) = 4.
# Scaled, J responds to k1, km1, k2, X0, X1 with [1, -0.2, 0.2, 1, 0] and S1
# with [1, -0.2, -0.8, 1, 0]; unscaled, J with [8, -3.2, 0.8, 0.8, 0] and S1
# with [4, -1.6, -1.6, 0.4, 0].
m = antimony.load("""
  $X0 -> S1; k1*X0 - km1*S1
  S1 -> $X1; k2*S1
  X0 = 10; X1 = 0; k1 = 1; km1 = 0.5; k2 = 2""")
r = antimony.response(m)
println(r.parameters, r.species, r.reactions, r.scaled)
println(approx(r.flux, [1.0, -0.2, 0.2, 1.0, 0.0; 1.0, -0.2, 0.2, 1.0, 0.0]),
        approx(r.concentration, [1.0, -0.2, -0.8, 1.0, 0.0]))
u = antimony.response(m, scaled = false)
println(u.scaled, approx(u.flux, [8.0, -3.2, 0.8, 0.8, 0.0; 8.0, -3.2, 0.8, 0.8, 0.0]),
        approx(u.concentration, [4.0, -1.6, -1.6, 0.4, 0.0]), approx(u.J, [8.0; 8.0]))

# A branched pathway with feedback and a conserved moiety: each scaled
# coefficient agrees with the change in the steady state when one parameter
# or boundary species is multiplied by 1 +- 1e-4 (X1 and X2 are 0, so 0).
function times(model, name, f)
  if haskey(model.parameters, name)
    model.parameters[name] = model.parameters[name] * f
  elseif model.boundary[name] != nothing      # one never assigned stays 0
    model.boundary[name] = model.boundary[name] * f
  end
  return model
end
b = antimony.load("""
  J0: $X0 -> S1; V0*X0/(K0 + X0)/(1 + S3/Ki)
  J1: S1 + ATP -> S2 + ADP; k1*S1*ATP
  J2: S2 -> S3; Vm2*S2/(Km2 + S2)
  J3: S3 -> $X1; k3*S3
  J4: S2 -> $X2; k4*S2
  J5: ADP -> ATP; k5*ADP
  X0 = 5; V0 = 10; K0 = 1; Ki = 2
  k1 = 1; Vm2 = 6; Km2 = 1; k3 = 2; k4 = 0.5; k5 = 3
  ATP = 3; ADP = 1""")
r = antimony.response(b)
println(r.parameters)
d = 1e-4
w = log(1 + d) - log(1 - d)
np = length(r.parameters)
RJ = zeros(length(r.J), np)
RS = zeros(length(r.y), np)
for k in 1:np
  up = times(b, r.parameters[k], 1 + d)
  down = times(b, r.parameters[k], 1 - d)
  s = antimony.steady_state(up, guess = r.y)
  t = antimony.steady_state(down, guess = r.y)
  RJ[:, k] = (log(antimony.fluxes(up, s.y)) - log(antimony.fluxes(down, t.y))) / w
  RS[:, k] = (log(s.y) - log(t.y)) / w
end
println(approx(RJ, r.flux, tol = 1e-6), approx(RS, r.concentration, tol = 1e-6))

try
  antimony.response(m, y = [1.0; 2.0])
catch err
  println(err.kind, err.message)
end
