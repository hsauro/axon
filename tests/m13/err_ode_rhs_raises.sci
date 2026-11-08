#! error: IndexError
# An error inside the right-hand side passes through CVODE unchanged.
import ode
s = ode.solve(function(t, y) return y[5] end, 1.0, [0, 1], method = "bdf")
