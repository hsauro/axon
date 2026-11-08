#! error: SolverError
import ode
s = ode.solve(function(t, y) return y .^ 2 end, 1.0, [0, 2], method = "bdf")
