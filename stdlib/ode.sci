## Ordinary differential equation solvers: RK45 (Dormand-Prince) and BDF
## (SUNDIALS CVODE). See the Language Reference, "The ode module". The
## stepping loops run natively in the core module odecore; this module checks
## the arguments and builds the result.

import odecore

EPS = 2.220446049250313e-16

# ---------------------------------------------------------------- helpers

# A real vector holding the values of x (a scalar, vector or matrix).
function real_vector(x)
  return reshape([x] + 0.0, length([x]))
end

function fail(kind, message)
  error(kind, "ode.solve: " + message)
end

# f(t, y) as a real vector of length n.
function call_rhs(f, t, y, n)
  d = f(t, y)
  if typeof(d) != "vector" and typeof(d) != "matrix" and typeof(d) != "real" and typeof(d) != "int"
    fail("TypeError", "the right-hand side must return a real vector, got " + typeof(d))
  end
  if length(d) != n
    fail("DimensionError", "the right-hand side returned " + string(length(d)) +
      " values, but y0 has " + string(n))
  end
  if eltype([d]) == "complex"
    fail("TypeError", "the right-hand side must return real values")
  end
  return real_vector(d)
end

# The value of event function g at (t, y), as a real number.
function call_event(g, t, y, k)
  v = g(t, y)
  if typeof(v) != "real" and typeof(v) != "int"
    fail("TypeError", "event function " + string(k) + " must return a real number, got " + typeof(v))
  end
  return v + 0.0
end

function wrms(v, w)
  return sqrt(sum((v ./ w) .^ 2) / length(v))
end

# Growable storage: a vector or an n-row matrix with spare capacity.
function grow_vector(v, k)
  if k <= length(v) return v end
  w = zeros(2 * length(v))
  w[1:length(v)] = v
  return w
end

function grow_matrix(M, k)
  [n, cap] = size(M)
  if k <= cap return M end
  W = zeros(n, 2 * cap)
  W[:, 1:cap] = M
  return W
end

function as_list(x, n, what)
  if typeof(x) == "list"
    if length(x) != n
      fail("ArgumentError", what + " needs one value per event (" + string(n) + "), got " +
        string(length(x)))
    end
    return x
  end
  l = {}
  for k in 1:n
    l = append(l, x)
  end
  return l
end

# True when g going from ga to gb is a zero crossing in the given direction.
function crosses(ga, gb, dir)
  if ga == 0 return false end
  up = ga < 0 and gb >= 0
  down = ga > 0 and gb <= 0
  if dir > 0 return up end
  if dir < 0 return down end
  return up or down
end

# The time in [ta, tb] where g(t, yat(t)) crosses zero (Illinois method).
function locate(g, k, yat, ta, ga, tb, gb)
  a = ta
  fa = ga
  b = tb
  fb = gb
  if fb == 0 return b end
  side = 0
  for it in 1:200
    c = (a * fb - b * fa) / (fb - fa)
    fc = call_event(g, c, yat(c), k)
    if fc == 0 return c end
    if (fc > 0) == (fb > 0)
      b = c
      fb = fc
      if side == -1 fa = fa / 2 end
      side = -1
    else
      a = c
      fa = fc
      if side == 1 fb = fb / 2 end
      side = 1
    end
    if abs(b - a) <= 4 * EPS * max(abs(a), abs(b)) + 1e-300 return b end
  end
  return b
end

# ---------------------------------------------------------------- output

# Collects the output points (t, y) and the event records.
function new_output(n)
  return {t: zeros(64), y: zeros(n, 64), count: 0}
end

function add_point(out, t, y)
  k = out.count + 1
  out.t = grow_vector(out.t, k)
  out.y = grow_matrix(out.y, k)
  out.t[k] = t
  out.y[:, k] = y
  out.count = k
  return out
end

# Output points for the step (told, tnew]: the step end, or the requested
# times that fall inside it.
function add_step_output(out, t_eval, next_eval, s, told, tnew, ynew, yat)
  if typeof(t_eval) == "nothing"
    return add_point(out, tnew, ynew), next_eval
  end
  while next_eval <= length(t_eval) and s * (t_eval[next_eval] - tnew) <= 0
    te = t_eval[next_eval]
    if te == tnew
      out = add_point(out, te, ynew)
    else
      out = add_point(out, te, yat(te))
    end
    next_eval = next_eval + 1
  end
  return out, next_eval
end

# ---------------------------------------------------------------- RK45

# Dormand-Prince 5(4) with Hairer's dense output (DOPRI5). The stepper runs
# in odecore (native); it returns the output points, the events and, per
# accepted step, its start, length and the five dense-output coefficients.
function rk45(f, t0, t1, y0, o)
  n = length(y0)
  s = 1.0
  if t1 < t0 s = -1.0 end
  [ot, oy, status, te_list, ye_list, nfev, nsteps, T0, H, R1, R2, R3, R4, R5] = odecore.rk45(
    f, t0, t1, y0, o)
  out = {t: ot, y: oy, count: length(ot)}
  steps = length(T0)
  at = function(tq)
    return dense_at(tq, n, s, T0, H, steps, function(j, th)
      th1 = 1 - th
      return R1[:, j] + th * (R2[:, j] + th1 * (R3[:, j] + th * (R4[:, j] + th1 * R5[:, j])))
    end)
  end
  return out, status, te_list, ye_list, nfev, nsteps, at
end

# y at time tq (or at each time of a vector tq) from per-step interpolants:
# step j starts at T0[j] and has length H[j]; poly(j, theta) evaluates it.
function dense_at(tq, n, s, T0, H, steps, poly)
  if typeof(tq) == "vector" or typeof(tq) == "matrix" or typeof(tq) == "range"
    tv = real_vector(tq)
    Y = zeros(n, length(tv))
    for k in 1:length(tv)
      Y[:, k] = dense_at(tv[k], n, s, T0, H, steps, poly)
    end
    return Y
  end
  if typeof(tq) != "real" and typeof(tq) != "int"
    fail("TypeError", "sol.at needs a time or a vector of times, got " + typeof(tq))
  end
  if steps == 0
    fail("DomainError", "sol.at: the solution has no steps")
  end
  tend = T0[steps] + H[steps]
  if s * (tq - T0[1]) < 0 or s * (tq - tend) > 0
    error("DomainError", "sol.at: t = " + string(tq) + " is outside the solution's range [" +
      string(T0[1]) + ", " + string(tend) + "]")
  end
  # Binary search for the step containing tq.
  lo = 1
  hi = steps
  while lo < hi
    mid = div(lo + hi + 1, 2)
    if s * (tq - T0[mid]) >= 0
      lo = mid
    else
      hi = mid - 1
    end
  end
  if H[lo] == 0 return poly(lo, 0.0) end
  return poly(lo, (tq - T0[lo]) / H[lo])
end

# ---------------------------------------------------------------- BDF (CVODE)

# CVODE's variable-order BDF, one step at a time, in odecore (native). The
# per-step data are the step's start and end states and derivatives, for a
# cubic Hermite sol.at.
function bdf(f, t0, t1, y0, o)
  n = length(y0)
  s = 1.0
  if t1 < t0 s = -1.0 end
  [ot, oy, status, te_list, ye_list, nfev, nsteps, T0, H, YA, YB, DA, DB] = odecore.bdf(
    f, t0, t1, y0, o)
  out = {t: ot, y: oy, count: length(ot)}
  steps = length(T0)
  at = function(tq)
    return dense_at(tq, n, s, T0, H, steps, function(j, th)
      # Cubic Hermite on step j.
      h = H[j]
      h00 = (1 + 2 * th) * (1 - th) ^ 2
      h10 = th * (1 - th) ^ 2
      h01 = th ^ 2 * (3 - 2 * th)
      h11 = th ^ 2 * (th - 1)
      return h00 * YA[:, j] + h10 * h * DA[:, j] + h01 * YB[:, j] + h11 * h * DB[:, j]
    end)
  end
  return out, status, te_list, ye_list, nfev, nsteps, at
end

# ---------------------------------------------------------------- solve

## Solves y' = f(t, y) from tspan[1] to tspan[2] with y(tspan[1]) = y0.
## method is "rk45" (explicit, the default) or "bdf" (stiff, CVODE). Returns a
## record with t, y (one column per time), names, status ("success" or
## "event"), t_events, y_events, nfev, nsteps and at(t) for dense output.
## With params set, f and the event functions are called as f(t, y, params).
export function solve(f, y0, tspan; method = "rk45", rtol = 1e-6, atol = 1e-9,
                      t_eval = nothing, events = nothing, terminal = false,
                      direction = 0, names = nothing, max_step = nothing,
                      first_step = nothing, max_steps = 100000, params = nothing)
  if typeof(f) != "function"
    fail("TypeError", "the right-hand side must be a function, got " + typeof(f))
  end
  if typeof(y0) != "real" and typeof(y0) != "int" and typeof(y0) != "vector" and typeof(y0) != "matrix"
    fail("TypeError", "y0 must be a real vector, got " + typeof(y0))
  end
  if eltype([y0]) == "complex"
    fail("TypeError", "y0 must be real")
  end
  y0 = real_vector(y0)
  n = length(y0)
  if n == 0 fail("DimensionError", "y0 is empty") end
  if typeof(tspan) == "list" or length(tspan) != 2
    fail("ArgumentError", "tspan must hold two times [t0, t1]")
  end
  t0 = tspan[1] + 0.0
  t1 = tspan[2] + 0.0
  if t0 == t1 fail("ArgumentError", "tspan must have t0 != t1") end
  s = 1.0
  if t1 < t0 s = -1.0 end
  if typeof(rtol) != "int" and typeof(rtol) != "real"
    fail("TypeError", "rtol must be a number, got " + typeof(rtol))
  end
  if not (rtol > 0)
    fail("ArgumentError", "rtol must be positive")
  end
  # atol: one number for every component, or a vector with one per component.
  if typeof(atol) == "int" or typeof(atol) == "real"
    if not (atol >= 0)
      fail("ArgumentError", "atol must be non-negative")
    end
    atol = atol + 0.0
  elseif typeof(atol) == "vector" or typeof(atol) == "range" or typeof(atol) == "matrix"
    atol = real_vector(atol)
    if length(atol) != n
      fail("DimensionError", "atol has " + string(length(atol)) + " values but y0 has " +
        string(n) + " components")
    end
    for a in atol
      if not (a >= 0)
        fail("ArgumentError", "atol must be non-negative, got " + string(a))
      end
    end
  else
    fail("TypeError", "atol must be a number or a vector, got " + typeof(atol))
  end
  if typeof(max_step) == "nothing" max_step = 1.0 / 0.0 end
  if max_step <= 0 fail("ArgumentError", "max_step must be positive") end
  if typeof(max_steps) != "int" or max_steps < 1
    fail("ArgumentError", "max_steps must be a positive int")
  end

  if typeof(t_eval) != "nothing"
    t_eval = real_vector(t_eval)
    for k in 1:length(t_eval)
      if s * (t_eval[k] - t0) < 0 or s * (t_eval[k] - t1) > 0
        fail("ArgumentError", "t_eval must lie within tspan")
      end
      if k > 1 and s * (t_eval[k] - t_eval[k - 1]) <= 0
        fail("ArgumentError", "t_eval must be strictly increasing in the direction of integration")
      end
    end
  end

  if typeof(events) == "nothing"
    events = {}
  elseif typeof(events) == "function"
    events = {events}
  elseif typeof(events) != "list"
    fail("TypeError", "events must be a function or a list of functions, got " + typeof(events))
  end
  for g in events
    if typeof(g) != "function"
      fail("TypeError", "events must be functions, got " + typeof(g))
    end
  end
  terminal = as_list(terminal, length(events), "terminal")
  direction = as_list(direction, length(events), "direction")

  if typeof(names) == "nothing"
    names = {}
    for k in 1:n
      names = append(names, "y" + string(k))
    end
  elseif typeof(names) != "list" or length(names) != n
    fail("ArgumentError", "names must be a list of " + string(n) + " strings")
  end

  o = {rtol: rtol + 0.0, atol: atol, t_eval: t_eval, events: events, terminal: terminal,
       direction: direction, max_step: max_step + 0.0, first_step: first_step, max_steps: max_steps,
       params: params}
  if method == "rk45"
    [out, status, te, ye, nfev, nsteps, at] = rk45(f, t0, t1, y0, o)
  elseif method == "bdf"
    [out, status, te, ye, nfev, nsteps, at] = bdf(f, t0, t1, y0, o)
  else
    fail("ArgumentError", "method must be \"rk45\" or \"bdf\", got \"" + string(method) + "\"")
  end
  k = out.count
  return {t: out.t[1:k], y: out.y[:, 1:k], names: names, status: status,
          t_events: te, y_events: ye, nfev: nfev, nsteps: nsteps, method: method, at: at}
end


# ---------------------------------------------------------------- integrators

## A solver kept between calls to advance: its method and relative
## tolerance, and a handle to the solver and its state.
export record Integrator
  method: string
  rtol: real
  handle: pointer
end

## A solver that keeps its state between calls to advance, for a solution
## advanced in steps, with parameters or the state changed between them.
## method is "rk45" or "bdf"; rtol and atol are as for solve.
export function integrator(f; method = "rk45", rtol = 1e-6, atol = 1e-9)
  if typeof(f) != "function"
    error("TypeError", "ode.integrator: the right-hand side must be a function, got " + typeof(f))
  end
  if method != "rk45" and method != "bdf"
    error("ArgumentError", "ode.integrator: method must be \"rk45\" or \"bdf\", got \"" +
      string(method) + "\"")
  end
  if (typeof(rtol) != "int" and typeof(rtol) != "real") or not (rtol > 0)
    error("ArgumentError", "ode.integrator: rtol must be a positive number")
  end
  if typeof(atol) == "int" or typeof(atol) == "real"
    if not (atol >= 0)
      error("ArgumentError", "ode.integrator: atol must be non-negative")
    end
    atol = atol + 0.0
  elseif typeof(atol) == "vector" or typeof(atol) == "range" or typeof(atol) == "matrix"
    atol = real_vector(atol)
    for a in atol
      if not (a >= 0)
        error("ArgumentError", "ode.integrator: atol must be non-negative, got " + string(a))
      end
    end
  else
    error("TypeError", "ode.integrator: atol must be a number or a vector, got " + typeof(atol))
  end
  return Integrator(method, rtol + 0.0, odecore.integrator(f, method, rtol + 0.0, atol))
end

## y at t1 > t, from y at t, with the integrator s. s continues from where
## its last advance ended when t, y and params are exactly what that call was
## given and returned; otherwise (the first call, or after a change) it
## starts afresh from (t, y). With params set, f is called as f(t, y, params).
export function advance(s, t, y, t1; params = nothing)
  if not isa(s, Integrator)
    error("TypeError", "ode.advance: s must be an integrator from ode.integrator, got " + typeof(s))
  end
  if (typeof(t) != "int" and typeof(t) != "real") or (typeof(t1) != "int" and typeof(t1) != "real")
    error("TypeError", "ode.advance: the times must be numbers")
  end
  if not (t1 > t)
    error("ArgumentError", "ode.advance: t1 must be later than t (got t = " + string(t) +
      ", t1 = " + string(t1) + ")")
  end
  if typeof(y) != "real" and typeof(y) != "int" and typeof(y) != "vector" and typeof(y) != "matrix"
    error("TypeError", "ode.advance: y must be a real vector, got " + typeof(y))
  end
  [v, nfev] = odecore.advance(s.handle, t + 0.0, real_vector(y), params, t1 + 0.0)
  return v
end
