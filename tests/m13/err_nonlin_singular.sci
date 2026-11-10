#! error: SolverError
# Two parallel lines: the Jacobian is singular.
import nonlin
r = nonlin.solve(function(x) return [x[1] + x[2]; 2 * x[1] + 2 * x[2] - 1] end, [0.0; 0.0])
