#! error: ArgumentError
import nonlin
r = nonlin.solve(function(x) return x end, [1.0], method = "bisection")
