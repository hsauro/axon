# s * n and n * s repeat a string, as repeat(s, n) does. Each line: the
# compiled result, whether the interpreter gives the same, and whether the
# function compiled.

function both(f, x)
  __jit_mode("on")
  a = f(x)
  __jit_mode("off")
  b = f(x)
  __jit_mode("on")
  println("[" + a + "]", a == b, __jit_compiled(f))
end

function rule(n)
  return "=" * n
end
function framed(word)
  bar = "-" * (length(word) + 4)
  return bar + " " + word + " " + bar
end
function twice_left(s)
  return 2 * s
end

both(rule, 5)
both(rule, 0)
both(framed, "axon")
both(twice_left, "ab")
println("xy" * 3 == repeat("xy", 3), 3 * "xy")
