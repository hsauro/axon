# ode.integrator and ode.advance: a solver kept between calls.
import ode
import odecore
from testing import approx

# y' = -k y, y(0) = 2: y = 2 exp(-k t).
f = function(t, y, p) return -p[1] * y end

for m in {"rk45", "bdf"}
  s = ode.integrator(f, method = m, rtol = 1e-9, atol = 1e-12)
  println(typeof(s), s.method, s.rtol)

  # 100 steps of 0.05 continue one solution: about the evaluations of one solve.
  one = ode.solve(f, 2.0, [0, 5], method = m, rtol = 1e-9, atol = 1e-12, params = [0.5])
  y = [2.0]
  t = 0.0
  for k in 1:100
    t1 = 0.05 * k
    [y, nfev] = odecore.advance(s.handle, t, y, [0.5], t1)
    t = t1
  end
  println(approx(y[1], 2 * exp(-2.5), tol = 1e-7), nfev < 1.3 * one.nfev)

  # A changed parameter restarts from the current state: k = 1 from t = 5.
  y = ode.advance(s, t, y, 6.0, params = [1.0])
  println(approx(y[1], 2 * exp(-2.5) * exp(-1.0), tol = 1e-7))

  # A changed state restarts too: y doubled at t = 6.
  y2 = ode.advance(s, 6.0, 2 * y, 7.0, params = [1.0])
  println(approx(y2[1], 4 * exp(-3.5) * exp(-1.0), tol = 1e-7))

  # One integrator used for two solutions in turn: each call starts afresh,
  # and both stay right.
  a = [1.0]
  b = [3.0]
  for k in 1:4
    a = ode.advance(s, k - 1.0, a, k + 0.0, params = [0.5])
    b = ode.advance(s, k - 1.0, b, k + 0.0, params = [0.5])
  end
  println(approx(a[1], exp(-2.0), tol = 1e-7), approx(b[1], 3 * exp(-2.0), tol = 1e-7))
end

# Without params, f takes two arguments.
g = function(t, y) return [y[2]; -y[1]] end
s = ode.integrator(g)
y = ode.advance(s, 0.0, [0.0; 1.0], pi / 2)
println(approx(y, [1.0; 0.0], tol = 1e-5))

# An error in f reaches the caller, and the integrator can still be used.
h = function(t, y, p)
  if t > 1 and p[1] < 0
    error("ValueError", "negative rate after t = 1")
  end
  return -y
end
s = ode.integrator(h)
try
  ode.advance(s, 0.0, [1.0], 2.0, params = [-1.0])
catch err
  println(err.kind, err.message)
end
println(approx(ode.advance(s, 0.0, [1.0], 2.0, params = [1.0])[1], exp(-2.0), tol = 1e-5))

# Checks.
for bad in {function() ode.advance(s, 1.0, [1.0], 1.0) end,
            function() ode.advance({handle: 1}, 0.0, [1.0], 1.0) end,
            function() ode.integrator(g, method = "euler") end,
            function() ode.integrator(g, rtol = 0) end,
            function() ode.integrator(1) end}
  try
    bad()
  catch err
    println(err.kind, err.message)
  end
end
