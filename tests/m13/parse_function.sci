# parse_function: functions made from text at run time.
f = parse_function("x, y", "2*sin(x) + y^2")
println(typeof(f), abs(f(1.0, 2.0) - (2 * sin(1.0) + 4.0)) < 1e-15)

# The whole-lambda form, for bodies of more than one line.
g = parse_function("function(x)\n  if x < 0\n    return -x\n  end\n  return x^2 - 1\nend")
println(g(-3), g(3.0))

# Elementwise operators evaluate over a vector at once.
h = parse_function("t", "exp(-t) .* cos(2 * pi * t)")
v = h([0.0; 0.5])
println(v[1], abs(v[2] + exp(-0.5)) < 1e-15)

# Built-in functions and constants are visible; the program's variables are not.
a = 10
k = parse_function("x", "x + pi")
println(k(1) == 1 + pi)
try
  parse_function("x", "x + a")
catch err
  println(err.kind, "-", err.message)
end

# Errors point into the expression.
for text in {"2*sinn(x)", "2*sin(x", "2 x"}
  try
    parse_function("x", text)
  catch err
    println(err.kind, "-", err.message)
  end
end

# A made function is an ordinary function: passed on, and compiled.
tri = parse_function("n", "n * (n + 1) / 2")
apply = function(fn, n) return fn(n) end
println(apply(tri, 4))
mode = __jit_mode("force")
println(tri(100), __jit_compiled(tri))
__jit_mode(mode)
