# ODE solves with right-hand sides that compile, against the same solves
# interpreted: the results must be identical.
import ode

p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}
lv = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2]; p.c*y[1]*y[2] - p.d*y[2]]
end
rob = function(t, y)
  return [-0.04*y[1] + 1e4*y[2]*y[3]; 0.04*y[1] - 1e4*y[2]*y[3] - 3e7*y[2]^2; 3e7*y[2]^2]
end

__jit_mode("on")
a = ode.solve(lv, [10.0; 5.0], [0, 50], rtol = 1e-8)
b = ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf", rtol = 1e-8, atol = 1e-12)
println(__jit_compiled(lv), __jit_compiled(rob))
__jit_mode("off")
c = ode.solve(lv, [10.0; 5.0], [0, 50], rtol = 1e-8)
d = ode.solve(rob, [1.0; 0.0; 0.0], [0, 40], method = "bdf", rtol = 1e-8, atol = 1e-12)
println(isequal(a.t, c.t), isequal(a.y, c.y), a.nfev == c.nfev)
println(isequal(b.t, d.t), isequal(b.y, d.y), b.nfev == d.nfev)
