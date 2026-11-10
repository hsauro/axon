# log10, log2 and atan2.
from testing import approx

inf = 1.0 / 0.0
nan = 0.0 / 0.0

# Exact powers of the base give exact integers.
println(log10(1000.0), log10(1e-5), log10(1e300), log10(10), typeof(log10(10)))
println(log2(8.0), log2(0.125), log2(1024), log2(2.0 ^ -1000))
bad = 0
for k in -300:300
  if log10(real("1e" + string(k))) != k bad = bad + 1 end
end
for k in -1000:1000
  if log2(2.0 ^ k) != k bad = bad + 1 end
end
println(bad)

# Other values, and the edges.
println(approx(log10(2.0), 0.30102999566398120, tol = 1e-15),
        approx(log2(3.0), 1.5849625007211562, tol = 1e-15),
        approx(log10(7.5), log(7.5) / log(10.0), tol = 1e-15))
println(log10(0.0), log10(-1.0), log2(0.0), log2(inf), log10(nan))

# Complex arguments give principal values; arrays work elementwise.
z = log10(-100 + 0i)
w = log2(-1 + 0i)
println(real(z), approx(imag(z), pi / log(10.0), tol = 1e-15), real(w),
        approx(imag(w), pi / log(2.0), tol = 1e-15))
println(log10([1.0; 10.0; 100.0])')

# atan2(y, x): the angle of (x, y), with C's handling of signs and infinities.
println(approx(atan2(1.0, 1.0), pi / 4, tol = 1e-15), approx(atan2(1, 0), pi / 2, tol = 1e-15),
        approx(atan2(-1, -1), -3 * pi / 4, tol = 1e-15))
println(atan2(0.0, -1.0) == pi, atan2(-0.0, -1.0) == -pi, atan2(0, 0))
println(atan2(1.0, inf), approx(atan2(inf, inf), pi / 4, tol = 1e-15),
        approx(atan2(-inf, -inf), -3 * pi / 4, tol = 1e-15))
println(approx(atan2([1.0; -1.0], 1.0), [pi / 4; -pi / 4], tol = 1e-15))
println(approx(atan2(1.0, [1.0, -1.0]), [pi / 4, 3 * pi / 4], tol = 1e-15))

# In a function, compiled when the JIT is on.
function polar(x, y)
  return sqrt(x^2 + y^2), atan2(y, x) * 180 / pi, log10(x^2 + y^2) / 2, log2(abs(x))
end
[r, a, d, b] = polar(3.0, 4.0)
println(r, approx(a, 53.130102354155979, tol = 1e-14), approx(d, log10(5.0), tol = 1e-15),
        approx(b, log2(3.0), tol = 1e-15))
[r, a, d, b] = polar(-8.0, 0.0)
println(r, a, approx(d, 0.90308998699194359, tol = 1e-15), b)

# deg2rad and rad2deg: the right angles are exact, and they undo each other.
println(deg2rad(180) == pi, deg2rad(90) == pi / 2, deg2rad(-360) == -2 * pi, rad2deg(pi), rad2deg(pi / 2))
println(approx(deg2rad(30), pi / 6, tol = 1e-15), approx(sin(deg2rad(30)), 0.5, tol = 1e-15),
        approx(rad2deg(deg2rad(37.5)), 37.5, tol = 1e-15), rad2deg(atan2(1.0, 1.0)))
println(rad2deg([0.0; pi / 4; pi])', deg2rad(90 + 0i) == pi / 2 + 0i)
function heading(x, y)
  return rad2deg(atan2(y, x)) + deg2rad(0)
end
println(heading(0.0, 1.0), heading(-1.0, 0.0))

try
  atan2(1 + 1i, 1.0)
catch err
  println(err.kind, err.message)
end
try
  log10("x")
catch err
  println(err.kind)
end
