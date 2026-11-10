#! error: IndexError
# An error inside f passes through KINSOL unchanged.
import nonlin
r = nonlin.solve(function(x) return x[3] end, [1.0; 2.0])
