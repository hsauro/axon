## The conservation matrix derived step by step from the QR factorisation of
## N' with column pivoting, and checked against antimony.conservation.

import antimony
import linalg
import fmt

model = antimony.load("""
    J0: -> S1;                    v0
    J1: S1 + ATP -> S2 + ADP;     k1*S1*ATP
    J2: S2 + NAD -> S3 + NADH;    k2*S2*NAD
    J3: S3 + ADP -> S4 + ATP;     k3*S3*ADP
    J4: S4 -> ;                   k4*S4
    J5: NADH -> NAD;              k5*NADH
    v0 = 1; k1 = 1; k2 = 1; k3 = 1; k4 = 1; k5 = 1
    ATP = 2; ADP = 1; NAD = 1; NADH = 0.5""")

## The conservation matrix Gamma of a stoichiometry matrix N, one row per
## conservation law and one column per species, with Gamma * N = 0. Returns
## Gamma, the independent species and the dependent ones (positions in N's
## rows), as antimony.conservation chooses them.
function conservation_matrix(N)
  [m, n] = size(N)
  # 1. N' P = Q R. The columns of N' are the species' rows of N; p lists
  #    them in the order the factorisation took them, largest first.
  [Q, R, p] = linalg.qrp(N')
  # 2. The rank: R's diagonal decreases, and entries that are zero up to
  #    rounding mark the species whose rows depend on the earlier ones.
  tol = max(m, n) * 2.2e-16 * abs(R[1, 1])
  r = 0
  while r < min(m, n) and abs(R[r + 1, r + 1]) > tol
    r = r + 1
  end
  ind = p[1:r]
  dep = p[(r + 1):m]
  # 3. N[ind, :] = R11' Q1' and N[dep, :] = R12' Q1', so the dependent rows
  #    are N[dep, :] = L0 N[ind, :] with L0 = (R11 \ R12)'.
  R11 = R[1:r, 1:r]
  R12 = R[1:r, (r + 1):m]
  L0 = (R11 \ R12)'
  # 4. Gamma = [-L0 I], its columns put back in the species' order: each row
  #    is a dependent species minus the combination of independent species
  #    that it equals. Rounding (adding 0.0 turns -0.0 into 0.0) removes the
  #    errors of the floating-point solve, as entries are whole numbers.
  Gamma = zeros(m - r, m)
  Gamma[:, ind] = 0.0 - L0
  Gamma[:, dep] = eye(m - r)
  return round(Gamma) + 0.0, ind, dep
end

## A conservation law as text, such as "ATP + ADP".
function law(g, names)
  text = ""
  for j in 1:length(g)
    if g[j] != 0
      if g[j] < 0
        text = text + " - "
      elseif text != ""
        text = text + " + "
      end
      if abs(g[j]) != 1
        text = text + format(abs(g[j]), 0) + " "
      end
      text = text + names[j]
    end
  end
  return text
end

N = antimony.stoichiometry(model)
species = antimony.species_names(model)
println(fmt.matrix(N, rows = species, cols = antimony.reaction_names(model),
                   decimals = 0))

# Steps 1 and 2 on their own: the species in the order the factorisation
# took them, with R's diagonal entries (R has one row per reaction, so the
# species after those have none).
[Q, R, p] = linalg.qrp(N')
k = size(R, 1)
d = zeros(k, 1)
for i in 1:k
  d[i, 1] = abs(R[i, i])
end
println(fmt.matrix(d, rows = species[p[1:k]], cols = {"|R[k, k]|"},
                   decimals = 4))
println("then:", species[p[(k + 1):length(p)]])

[Gamma, ind, dep] = conservation_matrix(N)
println("independent:", species[ind])
println("dependent:", species[dep])
println(fmt.matrix(Gamma, cols = species, decimals = 0))
println("largest entry of Gamma N:", max(abs(Gamma * N)))
totals = Gamma * antimony.initial(model)
for i in 1:size(Gamma, 1)
  println(law(Gamma[i, :], species) + " =", totals[i])
end

# antimony.conservation lists the dependent species in the model's order.
c = antimony.conservation(model)
same = isequal(c.gamma, Gamma[sortperm(dep), :])
println("same as antimony.conservation:", same)
