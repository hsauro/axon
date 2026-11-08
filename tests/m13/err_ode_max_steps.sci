#! error: SolverError
import ode
s = ode.solve(function(t, y) return -y end, 1.0, [0, 100], max_step = 0.1, max_steps = 50)
