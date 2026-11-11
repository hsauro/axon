# vector() and vector(x) in compiled code: the result type follows from x's
# type. Each line: the compiled result, whether the interpreter gives the
# same, and whether the function compiled.

function both(f, x)
  __jit_mode("on")
  a = f(x)
  __jit_mode("off")
  b = f(x)
  __jit_mode("on")
  println(string(a'), isequal(a, b), __jit_compiled(f))
end

# Growing a vector from vector(): append to a vector is not compiled yet,
# so this runs interpreted (the last field is false).
function halves(n: int)
  ts = vector()
  for k in 1:n
    ts = append(ts, k * 0.5)
  end
  return ts
end
both(halves, 3)

# A list of reals built in a loop, then made a vector.
function doubled(n: int)
  l = {}
  for k in 1:n
    l = append(l, k * 1.0)
  end
  return 2.0 * vector(l)
end
both(doubled, 4)

# A list of ints gives an int vector; a matrix gives its columns in turn.
function ints(n: int)
  return vector({n, n + 1, n + 2})
end
both(ints, 7)

function columns(A: matrix{real})
  return vector(A)
end
both(columns, [1.0, 2; 3, 4])

# A number gives a vector of length 1.
function one(x: real)
  return vector(x)
end
both(one, 2.5)
