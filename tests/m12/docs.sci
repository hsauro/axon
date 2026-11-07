## Small numerical helpers.
## Used by the REPL help tests.

## Euclidean norm of a real or complex vector.
## Returns a real scalar.
export function norm2(v: vector): real
  return sqrt(real(dot(v, v)))
end

## Integrates f from a to b with n trapezoids.
##
## The keyword n sets the number of panels.
export function trapz(f, a: real, b: real;
                      n: int = 100): real
  h = (b - a) / n
  s = (f(a) + f(b)) / 2
  for k in 1:n - 1
    s = s + f(a + k * h)
  end
  return h * s
end

export function undocumented(x)   # a comment, not a docstring
  return x
end

## Parameters of the Lotka-Volterra model.
export record LVParams
  a: real
  b: real
end

## Not exported.
function hidden()
  return 1
end
