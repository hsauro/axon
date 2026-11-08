## Ordinary differential equation solvers: RK45 (Dormand-Prince, written in
## Axon) and BDF (SUNDIALS CVODE through extern). See the Language Reference,
## "The ode module".

# ---------------------------------------------------------------- CVODE

extern "sundials_core"
  function SUNContext_Create(comm: ptr void, ctx: ref ptr void): int32
  function SUNContext_Free(ctx: ref ptr void): int32
  function SUNContext_ClearErrHandlers(ctx: ptr void): int32
  function N_VGetArrayPointer(v: ptr void): ptr void
  function N_VDestroy(v: ptr void)
  function SUNMatDestroy(a: ptr void)
  function SUNLinSolFree(ls: ptr void): int32
end

extern "sundials_cvode"
  type RhsFn = callback(t: float64, y: ptr void, ydot: ptr void, user: ptr void): int32
  type RootFn = callback(t: float64, y: ptr void, gout: ptr void, user: ptr void): int32
  function N_VNew_Serial(n: int64, ctx: ptr void): ptr void
  function SUNDenseMatrix(m: int64, n: int64, ctx: ptr void): ptr void
  function SUNLinSol_Dense(y: ptr void, a: ptr void, ctx: ptr void): ptr void
  function CVodeCreate(lmm: int32, ctx: ptr void): ptr void
  function CVodeInit(mem: ptr void, f: RhsFn, t0: float64, y0: ptr void): int32
  function CVodeSStolerances(mem: ptr void, rtol: float64, atol: float64): int32
  function CVodeSetLinearSolver(mem: ptr void, ls: ptr void, a: ptr void): int32
  function CVodeSetMaxNumSteps(mem: ptr void, mxsteps: clong): int32
  function CVodeSetMaxStep(mem: ptr void, hmax: float64): int32
  function CVodeSetInitStep(mem: ptr void, h: float64): int32
  function CVodeSetStopTime(mem: ptr void, tstop: float64): int32
  function CVodeRootInit(mem: ptr void, nrtfn: int32, g: RootFn): int32
  function CVodeGetRootInfo(mem: ptr void, rootsfound: ptr int32): int32
  function CVode(mem: ptr void, tout: float64, yout: ptr void, tret: ref float64, itask: int32): int32
  function CVodeGetDky(mem: ptr void, t: float64, k: int32, dky: ptr void): int32
  function CVodeGetNumRhsEvals(mem: ptr void, n: ref clong): int32
  function CVodeGetReturnFlagName(flag: clong): cstring
  function CVodeFree(mem: ref ptr void)
end

extern "libc"
  function copy_from_native(dst: ptr float64, src: ptr void, bytes: csize): ptr void name "memcpy"
  function copy_to_native(dst: ptr void, src: ptr float64, bytes: csize): ptr void name "memcpy"
end

EPS = 2.220446049250313e-16
CV_BDF = 2
CV_ONE_STEP = 2
CV_ROOT_RETURN = 2

# The problem being solved by CVODE. CVODE keeps its callbacks between calls,
# so they are two kept module functions that dispatch to this record; a solve
# saves and restores it, so a solve inside a right-hand side also works.
current = nothing

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

# Dormand-Prince 5(4) with Hairer's dense output (DOPRI5).
function rk45(f, t0, t1, y0, o)
  n = length(y0)
  s = 1.0
  if t1 < t0 s = -1.0 end
  out = new_output(n)
  next_eval = 1
  if typeof(o.t_eval) == "nothing"
    out = add_point(out, t0, y0)
  else
    while next_eval <= length(o.t_eval) and o.t_eval[next_eval] == t0
      out = add_point(out, t0, y0)
      next_eval = next_eval + 1
    end
  end

  # Dense output: per step its start, length and the five DOPRI5 coefficients.
  steps = 0
  T0 = zeros(64)
  H = zeros(64)
  R1 = zeros(n, 64)
  R2 = zeros(n, 64)
  R3 = zeros(n, 64)
  R4 = zeros(n, 64)
  R5 = zeros(n, 64)

  t = t0
  y = y0
  k1 = call_rhs(f, t, y, n)
  nfev = 1

  # Initial step (Hairer and Wanner, II.4).
  h = o.first_step
  if typeof(h) == "nothing"
    sk = o.atol + o.rtol * abs(y)
    d0 = wrms(y, sk)
    d1 = wrms(k1, sk)
    if d0 < 1e-5 or d1 < 1e-5
      h0 = 1e-6
    else
      h0 = 0.01 * d0 / d1
    end
    h0 = min(h0, abs(t1 - t0))
    y1 = y + s * h0 * k1
    f1 = call_rhs(f, t + s * h0, y1, n)
    nfev = nfev + 1
    d2 = wrms(f1 - k1, sk) / h0
    if max(d1, d2) <= 1e-15
      h1 = max(1e-6, h0 * 1e-3)
    else
      h1 = (0.01 / max(d1, d2)) ^ 0.2
    end
    h = min(100 * h0, h1)
  end
  h = min(min(abs(h), o.max_step), abs(t1 - t0))

  ng = length(o.events)
  gold = zeros(max(ng, 1))
  for k in 1:ng
    gold[k] = call_event(o.events[k], t, y, k)
  end
  te_list = {}
  ye_list = {}
  for k in 1:ng
    te_list = append(te_list, zeros(0))
    ye_list = append(ye_list, zeros(n, 0))
  end

  status = "success"
  facmax = 10.0
  done = false
  nsteps = 0
  while not done
    if nsteps >= o.max_steps
      fail("SolverError", "more than " + string(o.max_steps) + " steps before t = " + string(t1) +
        " (stopped at t = " + string(t) + ")")
    end
    if h < 16 * EPS * max(abs(t), 1e-300)
      fail("SolverError", "the step size became too small at t = " + string(t))
    end
    last = false
    if h >= abs(t1 - t)
      h = abs(t1 - t)
      last = true
    end
    hs = s * h

    k2 = call_rhs(f, t + hs / 5, y + hs * (k1 / 5), n)
    k3 = call_rhs(f, t + 3 * hs / 10, y + hs * (3 / 40 * k1 + 9 / 40 * k2), n)
    k4 = call_rhs(f, t + 4 * hs / 5, y + hs * (44 / 45 * k1 - 56 / 15 * k2 + 32 / 9 * k3), n)
    k5 = call_rhs(f, t + 8 * hs / 9, y + hs * (19372 / 6561 * k1 - 25360 / 2187 * k2 +
      64448 / 6561 * k3 - 212 / 729 * k4), n)
    k6 = call_rhs(f, t + hs, y + hs * (9017 / 3168 * k1 - 355 / 33 * k2 + 46732 / 5247 * k3 +
      49 / 176 * k4 - 5103 / 18656 * k5), n)
    ynew = y + hs * (35 / 384 * k1 + 500 / 1113 * k3 + 125 / 192 * k4 - 2187 / 6784 * k5 +
      11 / 84 * k6)
    tnew = t + hs
    if last tnew = t1 end
    k7 = call_rhs(f, tnew, ynew, n)
    nfev = nfev + 6
    errv = hs * (71 / 57600 * k1 - 71 / 16695 * k3 + 71 / 1920 * k4 - 17253 / 339200 * k5 +
      22 / 525 * k6 - 1 / 40 * k7)
    sk = o.atol + o.rtol * max(abs(y), abs(ynew))
    err = wrms(errv, sk)
    if err != err
      fail("SolverError", "the solution is not finite at t = " + string(t))
    end

    if err > 1
      # Rejected: retry with a smaller step.
      h = h * max(0.2, 0.9 * err ^ (-0.2))
      facmax = 1.0
      continue
    end

    # Accepted.
    nsteps = nsteps + 1
    ydiff = ynew - y
    bspl = hs * k1 - ydiff
    steps = steps + 1
    T0 = grow_vector(T0, steps)
    H = grow_vector(H, steps)
    R1 = grow_matrix(R1, steps)
    R2 = grow_matrix(R2, steps)
    R3 = grow_matrix(R3, steps)
    R4 = grow_matrix(R4, steps)
    R5 = grow_matrix(R5, steps)
    T0[steps] = t
    H[steps] = tnew - t
    R1[:, steps] = y
    R2[:, steps] = ydiff
    R3[:, steps] = bspl
    R4[:, steps] = ydiff - hs * k7 - bspl
    R5[:, steps] = hs * (-12715105075 / 11282082432 * k1 + 87487479700 / 32700410799 * k3 -
      10690763975 / 1880347072 * k4 + 701980252875 / 199316789632 * k5 -
      1453857185 / 822651844 * k6 + 69997945 / 29380423 * k7)
    j = steps
    yat = function(tq)
      th = (tq - T0[j]) / H[j]
      th1 = 1 - th
      return R1[:, j] + th * (R2[:, j] + th1 * (R3[:, j] + th * (R4[:, j] + th1 * R5[:, j])))
    end

    # Events in this step, earliest first.
    tstop = tnew
    ystop = ynew
    found = {}
    for k in 1:ng
      gnew = call_event(o.events[k], tnew, ynew, k)
      if crosses(gold[k], gnew, o.direction[k])
        found = append(found, {k: k, t: locate(o.events[k], k, yat, t, gold[k], tnew, gnew)})
      end
      gold[k] = gnew
    end
    if length(found) > 0
      # Sort by time in the direction of integration (few events: insertion sort).
      for a in 2:length(found)
        b = a
        while b > 1 and s * (found[b].t - found[b - 1].t) < 0
          tmp = found[b]
          found[b] = found[b - 1]
          found[b - 1] = tmp
          b = b - 1
        end
      end
      for e in found
        ye = yat(e.t)
        te_list[e.k] = append(te_list[e.k], e.t)
        ye_list[e.k] = reshape([ye_list[e.k], ye], n, length(te_list[e.k]))
        if o.terminal[e.k]
          tstop = e.t
          ystop = ye
          status = "event"
          break
        end
      end
    end

    [out, next_eval] = add_step_output(out, o.t_eval, next_eval, s, t, tstop, ystop, yat)
    if status == "event"
      H[steps] = tstop - t
      break
    end

    t = tnew
    y = ynew
    k1 = k7
    if last
      done = true
    else
      fac = min(facmax, max(0.2, 0.9 * err ^ (-0.2)))
      if err == 0 fac = facmax end
      h = min(h * fac, o.max_step)
      facmax = 10.0
    end
  end

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

function cvode_check(flag, what)
  if flag < 0
    fail("SolverError", "CVODE " + what + " failed (" + CVodeGetReturnFlagName(flag) + ")")
  end
end

function native_vector(v, n)
  y = zeros(n)
  copy_from_native(y, N_VGetArrayPointer(v), 8 * n)
  return y
end

function cvode_rhs(t, yv, ydotv, user)
  global current
  try
    y = native_vector(yv, current.n)
    d = call_rhs(current.f, t, y, current.n)
    copy_to_native(N_VGetArrayPointer(ydotv), d, 8 * current.n)
    current.nfev = current.nfev + 1
    return 0
  catch e
    current.err = e
    return -1
  end
end

function cvode_roots(t, yv, goutv, user)
  global current
  try
    y = native_vector(yv, current.n)
    g = zeros(length(current.events))
    for k in 1:length(current.events)
      g[k] = call_event(current.events[k], t, y, k)
    end
    copy_to_native(goutv, g, 8 * length(g))
    return 0
  catch e
    current.err = e
    return -1
  end
end

RHS = keep(cvode_rhs)
ROOTS = keep(cvode_roots)

function bdf(f, t0, t1, y0, o)
  global current
  n = length(y0)
  s = 1.0
  if t1 < t0 s = -1.0 end
  ng = length(o.events)
  saved = current
  current = {f: f, n: n, events: o.events, nfev: 0, err: nothing}

  ctx = nothing
  mem = nothing
  cvode_check(SUNContext_Create(nothing, ctx), "SUNContext_Create")
  # Failures come back as return codes; SUNDIALS should not also print them.
  SUNContext_ClearErrHandlers(ctx)
  yv = N_VNew_Serial(n, ctx)
  dky = N_VNew_Serial(n, ctx)
  A = SUNDenseMatrix(n, n, ctx)
  LS = SUNLinSol_Dense(yv, A, ctx)
  result = nothing
  failure = nothing
  try
    copy_to_native(N_VGetArrayPointer(yv), y0, 8 * n)
    mem = CVodeCreate(CV_BDF, ctx)
    cvode_check(CVodeInit(mem, RHS, t0, yv), "CVodeInit")
    cvode_check(CVodeSStolerances(mem, o.rtol, o.atol), "CVodeSStolerances")
    cvode_check(CVodeSetLinearSolver(mem, LS, A), "CVodeSetLinearSolver")
    cvode_check(CVodeSetMaxNumSteps(mem, o.max_steps), "CVodeSetMaxNumSteps")
    cvode_check(CVodeSetStopTime(mem, t1), "CVodeSetStopTime")
    if o.max_step < 1.0 / 0.0
      cvode_check(CVodeSetMaxStep(mem, o.max_step), "CVodeSetMaxStep")
    end
    if typeof(o.first_step) != "nothing"
      cvode_check(CVodeSetInitStep(mem, s * abs(o.first_step)), "CVodeSetInitStep")
    end
    if ng > 0
      cvode_check(CVodeRootInit(mem, ng, ROOTS), "CVodeRootInit")
    end

    out = new_output(n)
    next_eval = 1
    if typeof(o.t_eval) == "nothing"
      out = add_point(out, t0, y0)
    else
      while next_eval <= length(o.t_eval) and o.t_eval[next_eval] == t0
        out = add_point(out, t0, y0)
        next_eval = next_eval + 1
      end
    end
    # Dense output: cubic Hermite through the steps, with CVODE's derivative.
    steps = 0
    T0 = zeros(64)
    H = zeros(64)
    YA = zeros(n, 64)
    YB = zeros(n, 64)
    DA = zeros(n, 64)
    DB = zeros(n, 64)
    te_list = {}
    ye_list = {}
    for k in 1:ng
      te_list = append(te_list, zeros(0))
      ye_list = append(ye_list, zeros(n, 0))
    end

    t = t0
    y = y0
    dy = call_rhs(f, t0, y0, n)
    status = "success"
    tret = t0
    roots = int(zeros(max(ng, 1)))
    nsteps = 0
    while s * (t1 - t) > 0
      flag = CVode(mem, t1, yv, tret, CV_ONE_STEP)
      if typeof(current.err) != "nothing"
        error(current.err)
      end
      if flag < 0
        fail("SolverError", "CVODE failed at t = " + string(tret) + " (" +
          CVodeGetReturnFlagName(flag) + ")")
      end
      nsteps = nsteps + 1
      if nsteps > o.max_steps
        fail("SolverError", "more than " + string(o.max_steps) + " steps before t = " + string(t1) +
          " (stopped at t = " + string(tret) + ")")
      end
      ynew = native_vector(yv, n)
      cvode_check(CVodeGetDky(mem, tret, 1, dky), "CVodeGetDky")
      dnew = native_vector(dky, n)
      steps = steps + 1
      T0 = grow_vector(T0, steps)
      H = grow_vector(H, steps)
      YA = grow_matrix(YA, steps)
      YB = grow_matrix(YB, steps)
      DA = grow_matrix(DA, steps)
      DB = grow_matrix(DB, steps)
      T0[steps] = t
      H[steps] = tret - t
      YA[:, steps] = y
      YB[:, steps] = ynew
      DA[:, steps] = dy
      DB[:, steps] = dnew
      # Requested times inside this step come from CVODE's own interpolant.
      yat = function(tq)
        cvode_check(CVodeGetDky(mem, tq, 0, dky), "CVodeGetDky")
        return native_vector(dky, n)
      end
      tstop = tret
      if flag == CV_ROOT_RETURN
        cvode_check(CVodeGetRootInfo(mem, roots), "CVodeGetRootInfo")
        for k in 1:ng
          dir = roots[k]
          if dir != 0 and (o.direction[k] == 0 or o.direction[k] == dir)
            te_list[k] = append(te_list[k], tret)
            ye_list[k] = reshape([ye_list[k], ynew], n, length(te_list[k]))
            if o.terminal[k] status = "event" end
          end
        end
      end
      [out, next_eval] = add_step_output(out, o.t_eval, next_eval, s, t, tret, ynew, yat)
      t = tret
      y = ynew
      dy = dnew
      if status == "event" break end
    end
    nfev = current.nfev
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
    result = {out: out, status: status, te: te_list, ye: ye_list, nfev: nfev, nsteps: nsteps, at: at}
  catch e
    failure = e
  end
  if typeof(mem) != "nothing" CVodeFree(mem) end
  SUNLinSolFree(LS)
  SUNMatDestroy(A)
  N_VDestroy(yv)
  N_VDestroy(dky)
  SUNContext_Free(ctx)
  current = saved
  if typeof(failure) != "nothing" error(failure) end
  return result.out, result.status, result.te, result.ye, result.nfev, result.nsteps, result.at
end

# ---------------------------------------------------------------- solve

## Solves y' = f(t, y) from tspan[1] to tspan[2] with y(tspan[1]) = y0.
## method is "rk45" (explicit, the default) or "bdf" (stiff, CVODE). Returns a
## record with t, y (one column per time), names, status ("success" or
## "event"), t_events, y_events, nfev, nsteps and at(t) for dense output.
export function solve(f, y0, tspan; method = "rk45", rtol = 1e-6, atol = 1e-9,
                      t_eval = nothing, events = nothing, terminal = false,
                      direction = 0, names = nothing, max_step = nothing,
                      first_step = nothing, max_steps = 100000)
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
  if not (rtol > 0 and atol >= 0)
    fail("ArgumentError", "rtol must be positive and atol non-negative")
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

  o = {rtol: rtol + 0.0, atol: atol + 0.0, t_eval: t_eval, events: events, terminal: terminal,
       direction: direction, max_step: max_step + 0.0, first_step: first_step, max_steps: max_steps}
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
