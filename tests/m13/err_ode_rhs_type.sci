#! error: TypeError
import ode
s = ode.solve(function(t, y) return "fast" end, 1.0, [0, 1])
