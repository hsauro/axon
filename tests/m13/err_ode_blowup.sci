#! error: SolverError
# y' = y^2 with y(0) = 1 is 1/(1 - t), which blows up at t = 1.
import ode
s = ode.solve(function(t, y) return y .^ 2 end, 1.0, [0, 2])
