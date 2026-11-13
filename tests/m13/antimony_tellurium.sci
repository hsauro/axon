# antimony.control and antimony.response against libRoadRunner: the steady
# states, fluxes, scaled elasticities, scaled control coefficients and scaled
# response coefficients of the models in antimony_control.sci, as Tellurium
# computed them (tools/tellurium_mca_check.py wrote
# tellurium/mca_reference.json). libRoadRunner's response coefficients come
# from getCC one at a time, to about 1e-7; it gives none for a boundary
# species at 0 (NaN here), and adds the conserved totals (_CSUM0), which the
# comparison leaves out. Tellurium may list the species in
# another order, so rows and columns are matched by name. Both sides
# differentiate numerically, libRoadRunner with a larger step, so they agree
# to about 1e-7 where rate laws curve (Michaelis-Menten) and 1e-13 elsewhere.
import antimony
import io
from testing import approx

function index(names, name)
  for k in 1:length(names)
    if names[k] == name return k end
  end
  error("NameError", "Tellurium has no " + name)
end

# Tellurium's matrix t (t.values, named by t.rows and t.cols) with its rows in
# the order rows and its columns in the order cols.
function arranged(t, rows, cols)
  M = zeros(length(rows), length(cols))
  for i in 1:length(rows)
    for j in 1:length(cols)
      M[i, j] = t.values[index(t.rows, rows[i]), index(t.cols, cols[j])]
    end
  end
  return M
end

# Whether A agrees with R to tol where R is not NaN.
function close(A, R, tol)
  big = 1.0
  worst = 0.0
  for i in 1:size(R, 1)
    for j in 1:size(R, 2)
      if R[i, j] == R[i, j]
        big = max(big, abs(R[i, j]))
        worst = max(worst, abs(A[i, j] - R[i, j]))
      end
    end
  end
  return worst <= tol * big
end

ref = io.read_json("tellurium/mca_reference.json")
for r in ref.models
  c = antimony.control(antimony.load(r.source))
  y = zeros(length(c.species))
  for i in 1:length(c.species)
    y[i] = r.y[index(r.species, c.species[i])]
  end
  J = zeros(length(c.reactions))
  for i in 1:length(c.reactions)
    J[i] = r.J[index(r.reactions, c.reactions[i])]
  end
  println(r.name, approx(c.y, y, tol = 1e-12), approx(c.J, J, tol = 1e-12),
          approx(c.elasticities, arranged(r.elasticities, c.reactions, c.species), tol = 1e-6),
          approx(c.flux_control, arranged(r.flux_control, c.reactions, c.reactions), tol = 1e-6),
          approx(c.concentration_control,
                 arranged(r.concentration_control, c.species, c.reactions), tol = 1e-6))
  e = antimony.response(antimony.load(r.source))
  println(r.name, close(e.flux, arranged(r.flux_response, e.reactions, e.parameters), 1e-5),
          close(e.concentration,
                arranged(r.concentration_response, e.species, e.parameters), 1e-5))
end
