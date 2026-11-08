function both1(f, x)
  __jit_mode("on")
  a = f(x)
  __jit_mode("off")
  b = f(x)
  __jit_mode("on")
  println(string(a), string(a) == string(b), __jit_compiled(f))
end

function both3(f, x, y, z)
  __jit_mode("on")
  a = f(x, y, z)
  __jit_mode("off")
  b = f(x, y, z)
  __jit_mode("on")
  println(string(a), string(a) == string(b), __jit_compiled(f))
end

# The digits of the elements, in order.
function walk(a: int, h: int, b: int): int
  s = 0
  for k in a:h:b
    s = s * 10 + k
  end
  return s
end

function rcount(a: real, h: real, b: real): int
  n = 0
  for x in a:h:b
    n = n + 1
  end
  return n
end

function rlast(a: real, h: real, b: real): real
  last = a
  for x in a:h:b
    last = x
  end
  return last
end

# Changing the bound or the loop variable in the body changes nothing.
function bounds(n: int): int
  m = n
  c = 0
  for k in 1:m
    m = 1
    k = 100
    c = c + 1
  end
  return c
end

function skip3(n: int): int
  s = 0
  for k in 1:n
    if k == 3
      continue
    end
    if k > 5
      break
    end
    s = s + k
  end
  return s
end

function digits(x: real): int
  d = 1
  while x >= 10.0
    x = x / 10.0
    d = d + 1
  end
  return d
end

both3(walk, 1, 1, 5)
both3(walk, 5, -2, 1)
both3(walk, 3, 1, 1)
both3(walk, 1, 3, 8)
both3(rcount, 0.0, 0.1, 1.0)
both3(rcount, 1.0, -0.25, 0.0)
both3(rcount, 0.0, 1.0, -1.0)
both3(rlast, 0.0, 0.1, 1.0)
both1(bounds, 4)
both1(skip3, 10)
both1(digits, 12345.0)
