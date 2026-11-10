#! error: SolverError
# f(x0) is NaN.
import nonlin
r = nonlin.solve(function(x) return log(x) end, [-1.0])
