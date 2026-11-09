# ode.solve with one absolute tolerance per component.
import ode
rober = function(t, y)
  return [-0.04 * y[1] + 1e4 * y[2] * y[3];
          0.04 * y[1] - 1e4 * y[2] * y[3] - 3e7 * y[2]^2;
          3e7 * y[2]^2]
end
y0 = [1.0; 0.0; 0.0]
one = ode.solve(rober, y0, [0, 40], method = "bdf", rtol = 1e-4, atol = 1e-8)
each = ode.solve(rober, y0, [0, 40], method = "bdf", rtol = 1e-4, atol = [1e-8; 1e-14; 1e-6])
same = ode.solve(rober, y0, [0, 40], method = "bdf", rtol = 1e-4, atol = [1e-8; 1e-8; 1e-8])
println(each.status, abs(sum(each.y[:, end]) - 1.0) < 1e-6)
println(isequal(same.y, one.y), isequal(same.t, one.t))

f = function(t, y) return [-y[1]; -1000 * y[2]] end
one = ode.solve(f, [1.0; 1e-6], [0, 1], atol = 1e-9)
same = ode.solve(f, [1.0; 1e-6], [0, 1], atol = [1e-9; 1e-9])
tight = ode.solve(f, [1.0; 1e-6], [0, 1], atol = [1e-9; 1e-15])
println(isequal(same.y, one.y), tight.nsteps > one.nsteps)
println(abs(tight.y[1, end] - exp(-1.0)) < 1e-6)
