#! error: SolverError
# x^2 + 1 = 0 has no real root.
import nonlin
r = nonlin.solve(function(x) return x .^ 2 + 1 end, [1.0])
