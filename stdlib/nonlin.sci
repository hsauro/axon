## Nonlinear equations f(x) = 0, solved with SUNDIALS KINSOL: Newton's method
## with a line search, a dense linear solver and a Jacobian from difference
## quotients. See the Language Reference, "The nonlin module". The solve runs
## natively in the core module nonlincore; this module checks the arguments.

import nonlincore

function fail(kind, message)
  error(kind, "nonlin.solve: " + message)
end

function is_number(v)
  return typeof(v) == "int" or typeof(v) == "real"
end

## Solves f(x) = 0, starting from the guess x0 (a real vector, or a number
## for one equation). f(x) receives x as a real vector and returns a real
## vector of the same length. Returns a record with x (the solution, a real
## vector), status ("success", or "small_step" when Newton's steps stopped
## changing x before |f(x)| fell below ftol: check fnorm), fnorm (the
## Euclidean norm of f(x)), nfev (calls of f) and niters (Newton iterations).
## method is "linesearch" (the default) or "newton" (full steps). With params
## set, f is called as f(x, params).
export function solve(f, x0; method = "linesearch", ftol = 1e-10, xtol = 1e-12,
                      max_iters = 200, params = nothing)
  if typeof(f) != "function"
    fail("TypeError", "f must be a function, got " + typeof(f))
  end
  if not is_number(x0) and typeof(x0) != "vector" and typeof(x0) != "matrix"
    fail("TypeError", "x0 must be a real vector, got " + typeof(x0))
  end
  if eltype([x0]) == "complex"
    fail("TypeError", "x0 must be real")
  end
  x0 = reshape([x0] + 0.0, length([x0]))
  if length(x0) == 0
    fail("DimensionError", "x0 is empty")
  end
  if method != "linesearch" and method != "newton"
    fail("ArgumentError", "method must be \"linesearch\" or \"newton\", got \"" +
      string(method) + "\"")
  end
  if not is_number(ftol) or not (ftol > 0)
    fail("ArgumentError", "ftol must be a positive number")
  end
  if not is_number(xtol) or not (xtol > 0)
    fail("ArgumentError", "xtol must be a positive number")
  end
  if typeof(max_iters) != "int" or max_iters < 1
    fail("ArgumentError", "max_iters must be a positive int")
  end
  o = {method: method, ftol: ftol + 0.0, xtol: xtol + 0.0, max_iters: max_iters,
       params: params}
  [x, status, fnorm, nfev, niters] = nonlincore.kinsol(f, x0, o)
  return {x: x, status: status, fnorm: fnorm, nfev: nfev, niters: niters}
end
