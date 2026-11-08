#! error: ArgumentError
import ode
s = ode.solve(function(t, y) return -y end, 1.0, [1, 1])
