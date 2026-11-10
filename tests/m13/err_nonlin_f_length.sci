#! error: DimensionError
import nonlin
r = nonlin.solve(function(x) return [1.0; 2.0; 3.0] end, [1.0; 2.0])
