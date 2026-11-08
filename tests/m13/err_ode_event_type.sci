#! error: TypeError
import ode
s = ode.solve(function(t, y) return -y end, 1.0, [0, 1], events = function(t, y) return "x" end)
