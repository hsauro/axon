#! error: ArgumentError
import ode
s = ode.solve(function(t, y) return -y end, 1.0, [0, 1], t_eval = [0.5; 2.0])
