# The antimony module: reading a model, its stoichiometry, and simulating it.
import antimony
from testing import approx

m = antimony.load("""
    // A comment line, then a named and an unnamed reaction.
    A = 10                     # assigned before the reaction: still a species
    J1: 2 A + B -> C; k1*A*B
    C => ; k2*C                # "=>" and an empty side
    B = 4; k1 = 0.5; k2 = 2""")
println(antimony.species_names(m))
println(m.species, m.parameters)
for r in m.reactions
  println(r.name, r.reactants, r.products, r.rate)
end
println(antimony.stoichiometry(m))
println(antimony.initial(m)')

# The right-hand side at the start: v1 = 0.5*10*4 = 20, v2 = 0.
f = antimony.rhs(m)
println(f(0.0, antimony.initial(m))')

# A -> B with rate k*A: A = 2 exp(-k t), and A + B stays 2.
d = antimony.load("A -> B; k*A; A = 2; k = 0.5")
sol = antimony.simulate(d, 4.0, points = 5, rtol = 1e-9, atol = 1e-12)
println(sol.names, sol.t')
println(approx(sol.y[1, :], 2 * exp(-0.5 * sol.t), tol = 1e-7))
println(approx(sol.y[1, :] + sol.y[2, :], 2 * ones(5), tol = 1e-9))

# A species with no value starts at 0; a parameter whose value has no exact
# short text (1/3) is passed in a vector, with the same results.
e = antimony.load("A -> B; k*A; A = 3")
e.parameters["k"] = 1 / 3
s2 = antimony.simulate(e, 3.0, points = 4, method = "bdf", rtol = 1e-9, atol = 1e-12)
println(s2.y[2, 1], approx(s2.y[1, :], 3 * exp(-s2.t / 3), tol = 1e-6))

# A rate law may use only species and parameters.
try
  antimony.rhs(antimony.load("A -> B; k*A*Q; k = 1"))
catch err
  println(err.kind, err.message)
end

# Reading errors.
for bad in {"A -> B", "2 x y -> B; 1", "A = 1 = 2", ": A -> B; 1"}
  try
    antimony.load(bad)
  catch err
    println(err.message)
  end
end
