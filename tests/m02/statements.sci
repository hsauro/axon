local a
local b: int = 1
global g
x = 1
x: real = 2.0
A[1, 2] = 3
r.f = 4
r.f[2].g = 5
[p, q] = f()
function rf()
  return
  return 1
  return 1, 2
end
while true
  break
  continue
end
if a
  b = 1
elseif c
  b = 2
elseif d
else
  b = 3
end
if a
end
for i in 1:10
  s = s + i
end
while k < 10
  k = k + 1
end
try
  risky()
catch err
  print(err.message)
end
try
catch
end
function f(x, y: real; k = 1, m: int = k + 1): real
  return x
end
function g()
end
export function h(x)
  return x
end
record P
  a: real; b: matrix{complex}
  c: list
end
export record Q
  x: int
end
import linalg
import linalg as la
import ode.stiff
from linalg import eig, svd
extern "openblas"
  function ddot_(n: ref int32, x: ptr float64): float64
  function dgesv_(info: ref int32) name "dgesv"
  type RhsFn = callback(t: float64, user: ptr void): int32
  function cv(f: RhsFn, n: clong, s: csize)
end
