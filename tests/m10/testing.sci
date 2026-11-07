## Tolerance-aware comparisons for the numerical tests.

## True when a and b have the same shape and agree to tol, relative to the
## size of b (absolute below 1).
export function approx(a, b; tol = 1e-10)
  ta = typeof(a)
  if ta == "vector" or ta == "matrix"
    if ta != typeof(b) return false end
    [m1, n1] = size(a)
    [m2, n2] = size(b)
    if m1 != m2 or n1 != n2 return false end
    if length(a) == 0 return true end
    return max(abs(a - b)) <= tol * max(1.0, max(abs(b)))
  end
  return abs(a - b) <= tol * max(1.0, abs(b))
end

## True when every value of a matches a value of b, in any order.
export function approx_set(a, b; tol = 1e-10)
  if length(a) != length(b) return false end
  for x in a
    found = false
    for y in b
      if abs(x - y) <= tol * max(1.0, abs(y)) found = true end
    end
    if not found return false end
  end
  return true
end

## True when the columns of Q are orthonormal.
export function orthonormal(Q; tol = 1e-10)
  [m, n] = size(Q)
  return approx(adjoint(Q) * Q, eye(n), tol = tol)
end
