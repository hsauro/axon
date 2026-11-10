# nonlin.solve: Newton's method through KINSOL, with and without a line search.
import nonlin
from testing import approx

# A circle and a line: x = y = sqrt(2).
function circle(x)
  return [x[1]^2 + x[2]^2 - 4; x[1] - x[2]]
end
r = nonlin.solve(circle, [1.0; 1.0])
println(r.status, typeof(r.x), length(r.x), approx(r.x, [sqrt(2); sqrt(2)], tol = 1e-9))
println(r.fnorm < 1e-10, r.niters > 0, r.nfev > r.niters)

# One equation, with a number as the guess: cos x = x.
r = nonlin.solve(function(x) return cos(x[1]) - x[1] end, 1.0)
println(r.status, length(r.x), approx(r.x[1], 0.7390851332151607, tol = 1e-9))

# params, passed as f's second argument.
r = nonlin.solve(function(x, p) return x .^ 3 - p end, [1.0; 1.0; 1.0], params = [8.0; 27.0; 64.0])
println(approx(r.x, [2.0; 3.0; 4.0], tol = 1e-9))

# A linear system from x0 = 0 takes one Newton step.
r = nonlin.solve(function(x) return [2 - 0.5 * x[1]; 0.5 * x[1] - 4 * x[2]] end, [0.0; 0.0])
println(r.niters, approx(r.x, [4.0; 0.5], tol = 1e-12))

# A guess that is already a root: no iterations, one call of f.
r = nonlin.solve(circle, [sqrt(2); sqrt(2)])
println(r.status, r.niters, r.nfev)

# The gradient of Rosenbrock's function from (-1.2, 1): full Newton steps
# get there quickly; the line search follows the curved valley in many short
# steps.
function rb(x)
  return [-2 * (1 - x[1]) - 400 * x[1] * (x[2] - x[1]^2); 200 * (x[2] - x[1]^2)]
end
r = nonlin.solve(rb, [-1.2; 1.0], method = "newton")
println(approx(r.x, [1.0; 1.0], tol = 1e-9), r.niters < 20)
r = nonlin.solve(rb, [-1.2; 1.0], max_iters = 1000)
println(approx(r.x, [1.0; 1.0], tol = 1e-9), r.niters > 20)

# Solves nest: the outer f solves z^2 = x, and the outer root is z = 3.
outer = function(x) return nonlin.solve(function(z) return z .^ 2 - x[1] end, [1.0]).x - 3.0 end
r = nonlin.solve(outer, [4.0])
println(approx(r.x[1], 9.0, tol = 1e-8))
