#! error: DimensionError
import ode
s = ode.solve(function(t, y) return [1.0; 2.0] end, 1.0, [0, 1])
