#! error: ArgumentError
import ode
s = ode.solve(function(t, y) return -y end, 1.0, [0, 1], events = function(t, y) return y[1] end,
              terminal = {true, false})
