# Scalar arithmetic, compiled and interpreted: each line is the compiled
# result, whether the interpreter gives the same, and whether it compiled.

function both1(f, x)
  __jit_mode("on")
  a = f(x)
  __jit_mode("off")
  b = f(x)
  __jit_mode("on")
  println(string(a), string(a) == string(b), __jit_compiled(f))
end

function both2(f, x, y)
  __jit_mode("on")
  a = f(x, y)
  __jit_mode("off")
  b = f(x, y)
  __jit_mode("on")
  println(string(a), string(a) == string(b), __jit_compiled(f))
end

function iadd(a: int, b: int): int
  return a + b
end
function isub(a: int, b: int): int
  return a - b
end
function imul(a: int, b: int): int
  return a * b
end
function ineg(a: int): int
  return -a
end
function idiv(a: int, b: int)
  return a / b
end
function ibs(a: int, b: int)
  return a \ b
end
function ipow3(a: int)
  return a ^ 3
end
function ipow0(a: int)
  return a ^ 0
end
function ipowneg(a: int)
  return a ^ -2
end
function rpow(x: real, y: real)
  return x ^ y
end
function bplus(p: bool, q: bool)
  return p + q
end
function bneg(p: bool)
  return -p
end
function rdiv(x: real, y: real)
  return x / y
end
function mixed(a: int, x: real)
  return a * x - a
end

both2(iadd, 2, 3)
both2(isub, 2, 5)
both2(imul, -4, 6)
both1(ineg, 7)
both2(idiv, 7, 2)
both2(idiv, 1, 0)
both2(ibs, 2, 7)
both1(ipow3, -3)
both1(ipow0, 0)
both1(ipowneg, 2)
both2(rpow, 2.0, 10.0)
both2(rpow, -2.0, 3.0)
both2(rpow, -8.0, 0.5)
both2(bplus, true, true)
both1(bneg, true)
both2(rdiv, 0.0, 0.0)
both2(rdiv, -1.0, 0.0)
both2(mixed, 3, 0.5)
both2(iadd, true, 2)
both2(mixed, 2, 4)
