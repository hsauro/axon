# div and mod of reals: floor division and its remainder (the sign of the
# divisor), NaN for a zero divisor. Compiled code calls the interpreter's
# own routines directly. Each line: the compiled results, then whether the
# interpreter gives the same.

function dm(x, y)
  return {d: div(x, y), m: mod(x, y)}
end

function both(x, y)
  __jit_mode("on")
  a = dm(x, y)
  __jit_mode("off")
  b = dm(x, y)
  __jit_mode("on")
  println(string(a.d) + " " + string(a.m) + " " +
          string(string(a.d) == string(b.d) and string(a.m) == string(b.m)))
end

both(7.5, 2.0)
both(-7.5, 2.0)
both(7.5, -2.0)
both(5, 2.5)
both(5.0, 0.0)
both(0.0, -5.0)
both(1.0 / 0.0, 2.0)

# Quotients beyond the range of a 32-bit integer stay exact.
println(div(3.0e9, 1.0) == 3.0e9)
println(div(1.0e300, 1.0) == 1.0e300)
println(mod(-3.0e9 - 0.5, 1.0))
