# A large model: Millard et al.'s E. coli core metabolism (tellurium/ecoli.ant:
# 64 floating species, 68 reactions, three compartments, three assignment
# rules, ln in rate laws), against libRoadRunner's results in
# tellurium/ecoli_reference.json (written by tools/tellurium_mca_check.py).
# Tellurium lists species in another order, so they are matched by name.
import antimony
import io
from testing import approx

function index(names, name)
  for k in 1:length(names)
    if names[k] == name return k end
  end
  error("NameError", "Tellurium has no " + name)
end

# Tellurium's matrix t with its rows and columns in the given orders.
function arranged(t, rows, cols)
  M = zeros(length(rows), length(cols))
  for i in 1:length(rows)
    for j in 1:length(cols)
      M[i, j] = t.values[index(t.rows, rows[i]), index(t.cols, cols[j])]
    end
  end
  return M
end

# Whether each entry of A is within tol of R's, relative to max(1, |R|).
function close(A, R, tol)
  for i in 1:size(R, 1)
    for j in 1:size(R, 2)
      if abs(A[i, j] - R[i, j]) > tol * max(1.0, abs(R[i, j]))
        return false
      end
    end
  end
  return true
end

m = antimony.read("tellurium/ecoli.ant")
println(length(antimony.species_names(m)), length(antimony.boundary_names(m)),
        length(m.reactions), length(m.parameters), keys(m.compartments), keys(m.rules))

# The rates compiled and interpreted agree. (MIR v1.0.0's optimiser compiled
# two of these 68 rate laws wrongly; fixed by the newer MIR.)
y0 = antimony.initial(m)
p = antimony.parameter_values(m)
old = __jit_mode("off")
interpreted = antimony.rates(m)
vi = interpreted(y0, p)
__jit_mode("on")
compiled = antimony.rates(m)
vc = compiled(y0, p)
__jit_mode(old)
println(approx(vc, vi, tol = 1e-13))

# Steady state and fluxes (the compartments' sizes matter: two of them are
# not 1), elasticities and control coefficients. Both sides differentiate
# numerically, libRoadRunner with a larger step, so they agree to about 1e-5.
ref = io.read_json("tellurium/ecoli_reference.json")
c = antimony.control(m)
y = zeros(length(c.species))
for i in 1:length(c.species)
  y[i] = ref.y[index(ref.species, c.species[i])]
end
J = zeros(length(c.reactions))
for i in 1:length(c.reactions)
  J[i] = ref.J[index(ref.reactions, c.reactions[i])]
end
println(approx(c.y, y, tol = 1e-10), approx(c.J, J, tol = 1e-10))
println(close(c.elasticities, arranged(ref.elasticities, c.reactions, c.species), 1e-4),
        close(c.flux_control, arranged(ref.flux_control, c.reactions, c.reactions), 1e-4),
        close(c.concentration_control,
              arranged(ref.concentration_control, c.species, c.reactions), 1e-4))
println(max(abs(sum(c.flux_control, 2) - 1)) < 1e-10,
        max(abs(sum(c.concentration_control, 2))) < 1e-10)
