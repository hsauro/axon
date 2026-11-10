#! error: TypeError
import nonlin
r = nonlin.solve(function(x) return x end, {1.0})
