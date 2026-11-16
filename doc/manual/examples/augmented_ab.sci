## The augmented steady-state system for A <-> B, built by hand: the
## stoichiometry matrix, the conservation basis K, F(y) solved by Newton's
## method, and the Jacobian's eigenvalues.

import antimony
import linalg
import nonlin
import fmt

k1 = 2.0
k2 = 1.0
y0 = [3.0; 0.0]                  # A and B at the start: T = A + B = 3

N = [-1.0,  1.0;                 # A: used by J1, made by J2
      1.0, -1.0]                 # B: made by J1, used by J2
K = linalg.null(N')              # the conserved directions, length 1
println("N:")
println(fmt.matrix(N, decimals = 0))
println("K:")
println(fmt.matrix(K, decimals = 4))
println("K K':")
println(fmt.matrix(K * K', decimals = 2))

# The rates, and the augmented system: rates of change plus the part of
# y - y0 that no reaction could have made.
function rates(y)
  return [k1 * y[1]; k2 * y[2]]
end

function F(y)
  return N * rates(y) + K * (K' * y - K' * y0)
end

# A vector's values on one line.
function row(v)
  return fmt.matrix(v', decimals = 4)
end

s = nonlin.solve(F, y0)
println("steady state:", row(s.x), " A + B =", sum(s.x))

# The Jacobians: N dv/dy alone is singular; adding K K' mends it.
Jv = N * [k1, 0.0; 0.0, k2]
println("eigenvalues of N dv/dy:", row(sort(linalg.eig(Jv))))
println("eigenvalues of J_F:", row(sort(linalg.eig(Jv + K * K'))))

# The same steady state from the antimony module.
model = antimony.load("""
    J1: A -> B;   k1*A
    J2: B -> A;   k2*B
    k1 = 2; k2 = 1; A = 3; B = 0""")
println("antimony:", row(antimony.steady_state(model, method = "augmented").y))
