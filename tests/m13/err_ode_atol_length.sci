#! error: DimensionError
import ode
ode.solve(function(t, y) return -y end, [1.0; 2.0], [0, 1], atol = [1e-6])
