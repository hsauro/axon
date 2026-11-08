# Comparisons as bit codes: == 1, != 2, < 4, <= 8, > 16, >= 32.

function both2(f, x, y)
  __jit_mode("on")
  a = f(x, y)
  __jit_mode("off")
  b = f(x, y)
  __jit_mode("on")
  println(a, a == b, __jit_compiled(f))
end

function code_real(x: real, y: real): int
  c = 0
  if x == y
    c = c + 1
  end
  if x != y
    c = c + 2
  end
  if x < y
    c = c + 4
  end
  if x <= y
    c = c + 8
  end
  if x > y
    c = c + 16
  end
  if x >= y
    c = c + 32
  end
  return c
end

function code_int(a: int, b: int): int
  c = 0
  if a == b
    c = c + 1
  end
  if a != b
    c = c + 2
  end
  if a < b
    c = c + 4
  end
  if a <= b
    c = c + 8
  end
  if a > b
    c = c + 16
  end
  if a >= b
    c = c + 32
  end
  return c
end

function code_mixed(a: int, x: real): int
  c = 0
  if a == x
    c = c + 1
  end
  if a < x
    c = c + 4
  end
  if a > x
    c = c + 16
  end
  return c
end

function code_bool(p: bool, q: bool): int
  c = 0
  if p == q
    c = c + 1
  end
  if p > q
    c = c + 16
  end
  return c
end

# Short-circuiting: the right operand would overflow.
function either(a: int): bool
  return a > 0 or a * a > 10
end
function both_signs(a: int): bool
  return a < 0 and a * a > 10
end
function negate(p: bool): bool
  return not p
end

nan = 0.0 / 0.0
both2(code_real, 1.0, 2.0)
both2(code_real, 2.0, 2.0)
both2(code_real, nan, 1.0)
both2(code_real, nan, nan)
both2(code_int, 3, 2)
both2(code_int, -5, -5)
both2(code_mixed, 1, 1.0)
both2(code_mixed, 1, 1.5)
both2(code_mixed, 2, nan)
both2(code_bool, true, false)
both2(code_bool, false, false)
__jit_mode("on")
println(either(4611686018427387904), both_signs(4611686018427387904), negate(false))
println(__jit_compiled(either), __jit_compiled(both_signs), __jit_compiled(negate))
