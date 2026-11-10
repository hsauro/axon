## Solving nonlinear equations with nonlin.solve.

import nonlin

# Where the circle x^2 + y^2 = 4 meets the parabola y = x^2 - 1.
function f(v)
  x = v[1]
  y = v[2]
  return [x^2 + y^2 - 4; y - (x^2 - 1)]
end

r = nonlin.solve(f, [1.0; 1.0])
println("status:", r.status, " iterations:", r.niters, " calls of f:", r.nfev)
println("x =", format(r.x[1], 6), " y =", format(r.x[2], 6), " |f| =", r.fnorm)

# The radius as a parameter, passed to g as its second argument.
function g(v, radius)
  return [v[1]^2 + v[2]^2 - radius^2; v[2] - (v[1]^2 - 1)]
end
for radius in {1.5, 2.0, 3.0}
  r = nonlin.solve(g, [1.0; 1.0], params = radius)
  println("radius =", radius, " x =", format(r.x[1], 6), " y =", format(r.x[2], 6))
end
