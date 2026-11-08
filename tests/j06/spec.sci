# Functions without annotations, compiled for the types they are called
# with. Each line: the compiled result, whether the interpreter gives the
# same, and whether the function compiled (for some argument types).

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

function fib(n)
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

function sq(x)
  return x * x
end

function trace(A: matrix)
  s = 0.0
  for i in 1:size(A, 1)
    s = s + A[i, i]
  end
  return s
end

function vsum(v: vector)
  s = v[1] - v[1]
  for x in v
    s = s + x
  end
  return s
end

# The parameter changes type: interpreted for an int, compiled for a real.
function changes(x)
  x = 2.5
  return x
end

function add(a, b)
  return a + b
end

both1(fib, 20)
both1(sq, 3)
both1(sq, 1.5)
both1(trace, [1.0, 2.0; 3.0, 4.0])
both1(vsum, [1; 2; 3])
both1(vsum, [0.5; 0.25])
both1(changes, 1)
both1(changes, 1.0)

# At most 8 sets of argument types per function; the ninth runs interpreted.
__jit_mode("on")
print(add(1, 2), add(1, 2.0), add(1.0, 2), add(1.0, 2.0), add(true, 1), add(1, true),
  add(true, true), add(true, 1.0), add(1.0, true))
print(__jit_reason(add))
