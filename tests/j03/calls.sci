# Calls in compiled code: each line is the compiled result, whether the
# interpreter gives the same, and whether the function compiled.

function both1(f, x)
  __jit_mode("on")
  a = f(x)
  __jit_mode("off")
  b = f(x)
  __jit_mode("on")
  print(string(a), string(a) == string(b), __jit_compiled(f))
end

function both2(f, x, y)
  __jit_mode("on")
  a = f(x, y)
  __jit_mode("off")
  b = f(x, y)
  __jit_mode("on")
  print(string(a), string(a) == string(b), __jit_compiled(f))
end

function fib(n: int): int
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

function hyp(x: real, y: real): real
  return sqrt(x * x + y * y)
end

function dm(a: int, b: int)
  return div(a, b), mod(a, b)
end

function use_dm(a: int, b: int): int
  [q, r] = dm(a, b)
  return q * 100 + r
end

function rounding(x: real): int
  return floor(x) * 1000000 + ceil(x) * 10000 + round(x) * 100 + int(x)
end

function mm(a: int, x: real): real
  return min(a, x) + max(a, x)
end

function absall(a: int, x: real): real
  return abs(a) + abs(x)
end

function realdivmod(x: real, y: real): real
  return div(x, y) * 10 + mod(x, y)
end

# Runs interpreted (an unannotated parameter); its result type is declared.
function legacy(x): real
  return x * 2
end

function via_interp(a: real): real
  return legacy(a) + 1
end

function talk(n: int)
  print("talk:", n, n / 2, n > 2)
end

# Mutual recursion: one direction goes through the interpreter.
function is_even(n: int): bool
  if n == 0
    return true
  end
  return is_odd(n - 1)
end

function is_odd(n: int): bool
  if n == 0
    return false
  end
  return is_even(n - 1)
end

both1(fib, 20)
both2(hyp, 3.0, 4.0)
both2(use_dm, -7, 2)
both1(rounding, 2.5)
both1(rounding, -2.5)
both2(mm, 2, 3.5)
both2(absall, -3, -2.5)
both2(realdivmod, 7.5, 2.0)
both1(via_interp, 1.5)
both1(is_even, 10)
both1(is_odd, 7)
print(__jit_compiled(dm), __jit_compiled(legacy), __jit_reason(legacy))
__jit_mode("on")
talk(3)
print(__jit_compiled(talk))

# The guard: a compiled call follows a variable that is rebound.
function double(x: int): int
  return x * 2
end
function triple(x: int): int
  return x * 3
end
function apply(x: int): int
  return double(x)
end
print(apply(5), __jit_compiled(apply))
double = triple
print(apply(5))
