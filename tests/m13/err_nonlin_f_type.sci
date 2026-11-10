#! error: TypeError
import nonlin
r = nonlin.solve(function(x) return "zero" end, [1.0])
