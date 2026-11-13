## Reads reaction models written in a basic subset of Antimony, and simulates
## them. A model is reactions, each with a rate law, and numeric assignments:
##
##   J1: 2 A + B -> C; k1*A*B     // named reaction ("J1:" may be left out)
##   C -> ; k2*C                  # a side may be empty
##   A = 10; B = 5; k1 = 0.1; k2 = 0.05
##
## Statements end at ";" or at the end of a line, and "//" or "#" starts a
## comment. "->" and "=>" are both read as reactions. Assigned names that
## appear in a reaction are species (initial values); the rest are
## parameters. "$X" in a reaction makes X a boundary species, held fixed:
##   $X0 -> S1; k1*X0             # a source at a fixed concentration
## so the species that change are the floating ones. simulate solves a whole time span; simulator, step and set
## advance a simulation in steps, changing values between them; steady_state
## finds where the species stop changing. See the Language Reference, "The
## antimony module".

import io
import linalg
import nonlin
import ode

## One reaction: its name, the stoichiometric coefficients of the species it
## consumes and produces (dictionaries from name to number) and its rate law
## as written.
export record Reaction
  name: string
  reactants: dict
  products: dict
  rate: string
end

## A model: its reactions in order, its floating species (name to initial
## value, or nothing when none was assigned) in the order they first appear,
## its parameters (name to value) in the order they were assigned, and its
## boundary species ($X in a reaction: name to value, or nothing), which stay
## fixed, in the order they first appear.
export record Model
  reactions: list
  species: dict
  parameters: dict
  boundary: dict
end


# ------------------------------------------------------------ reading

# An int when the text is a whole number, otherwise a real.
function read_number(s)
  try
    return int(s)
  catch
    return real(s)
  end
end


# The line without its comment, if it has one.
function strip_comment(line)
  for mark in {"//", "#"}
    k = find(line, mark)
    if k > 0
      line = line[1:k - 1]
    end
  end
  return line
end


# The statements of the source, trimmed, comments and empty ones dropped.
function statements_of(source)
  result = {}
  for line in split(source, "\n")
    for s in split(strip_comment(line), ";")
      s = trim(s)
      if s != ""
        result = append(result, s)
      end
    end
  end
  return result
end


# "2 A + B" as dict("A" => 2, "B" => 1); an empty side gives an empty dict.
function parse_side(side)
  result = dict()
  if trim(side) == ""
    return result
  end
  for term in split(side, "+")
    parts = split(trim(term))
    if length(parts) == 1
      coefficient = 1
      name = parts[1]
    elseif length(parts) == 2
      coefficient = read_number(parts[1])
      name = parts[2]
    else
      error("Invalid species term: '" + trim(term) + "'")
    end
    result[name] = get(result, name, 0) + coefficient
  end
  return result
end


# The side with "$" taken off the names of boundary species, and boundary
# with those names added.
function strip_boundary(side, boundary)
  result = dict()
  for name in keys(side)
    plain = name
    if startswith(name, "$")
      plain = trim(name[2:end])
      if plain == ""
        error("Invalid species term: '" + name + "'")
      end
      boundary[plain] = nothing
    end
    result[plain] = get(result, plain, 0) + side[name]
  end
  return result, boundary
end


# The arrow in a reaction ("->" or "=>"), or nothing if it is not a reaction.
function arrow_of(statement)
  for arrow in {"->", "=>"}
    if contains(statement, arrow)
      return arrow
    end
  end
  return nothing
end


## The model in the text source.
export function load(source)
  statements = statements_of(source)
  reactions = {}
  species = dict()    # every name in a reaction
  boundary = dict()   # the names marked with "$" anywhere
  values = dict()     # every assignment; split into species and parameters at the end
  unnamed = 0         # reactions given no name so far

  i = 1
  while i <= length(statements)
    statement = statements[i]
    arrow = arrow_of(statement)

    if arrow != nothing
      # An optional name before a colon, "J1: A -> B"; unnamed reactions
      # are called _J0, _J1, ... in order, as in Antimony.
      k = find(statement, ":")
      if k > 0
        name = trim(statement[1:k - 1])
        statement = trim(statement[k + 1:end])
        if name == ""
          error("Missing reaction name before ':' in: " + statements[i])
        end
      else
        name = "_J" + string(unnamed)
        unnamed = unnamed + 1
      end

      sides = split(statement, arrow)
      if length(sides) != 2
        error("Invalid reaction: " + statement)
      end
      [reactants, boundary] = strip_boundary(parse_side(sides[1]), boundary)
      [products, boundary] = strip_boundary(parse_side(sides[2]), boundary)
      for side in {reactants, products}
        for s in keys(side)
          species[s] = nothing
        end
      end

      # The rate law is the next statement.
      i = i + 1
      if i > length(statements)
        error("Missing rate law for reaction: " + statement)
      end
      reactions = append(reactions, Reaction(name, reactants, products, statements[i]))
    else
      parts = split(statement, "=")
      if length(parts) != 2
        error("Invalid assignment: " + statement)
      end
      name = trim(parts[1])
      if startswith(name, "$")
        name = trim(name[2:end])
        boundary[name] = nothing
      end
      values[name] = read_number(trim(parts[2]))
    end

    i = i + 1
  end

  # A name marked "$" once is a boundary species everywhere, as in Antimony;
  # the others in reactions float.
  floating = dict()
  for name in keys(species)
    if not haskey(boundary, name)
      floating[name] = nothing
    end
  end

  # Assignments may come before or after the reactions that use a name.
  parameters = dict()
  for name in keys(values)
    if haskey(floating, name)
      floating[name] = values[name]
    elseif haskey(boundary, name)
      boundary[name] = values[name]
    else
      parameters[name] = values[name]
    end
  end

  return Model(reactions, floating, parameters, boundary)
end


## The model in the file at path.
export function read(path)
  return load(io.read_file(path))
end


# ------------------------------------------------------------ analysis

## The species names, in the order of the rows of stoichiometry(model) and
## the components of a simulation: the floating species, not the boundary
## ones.
export function species_names(model)
  return keys(model.species)
end


## The boundary species' names ($X), in the order they first appear.
export function boundary_names(model)
  return keys(model.boundary)
end


## The names of the values in parameter_values(model): the parameters, then
## the boundary species.
export function parameter_names(model)
  names = keys(model.parameters)
  for b in keys(model.boundary)
    names = append(names, b)
  end
  return names
end


## The stoichiometry matrix: one row per species, in the order of
## species_names(model), and one column per reaction.
export function stoichiometry(model)
  names = keys(model.species)
  N = zeros(length(names), length(model.reactions))
  for j in 1:length(model.reactions)
    r = model.reactions[j]
    for i in 1:length(names)
      N[i, j] = get(r.products, names[i], 0) - get(r.reactants, names[i], 0)
    end
  end
  return N
end


## The initial values of the species as a real vector; a species with no
## assigned value starts at 0.
export function initial(model)
  names = keys(model.species)
  y0 = zeros(length(names))
  for i in 1:length(names)
    v = model.species[names[i]]
    if v != nothing
      y0[i] = v
    end
  end
  return y0
end


# c*v as a term of a sum: "+ v", "- 2.0*v", ... ("" for c = 0).
function term(c, v)
  if c == 0
    return ""
  elseif c == 1
    return " + " + v
  elseif c == -1
    return " - " + v
  elseif c > 0
    return " + " + string(c) + "*" + v
  else
    return " - " + string(-c) + "*" + v
  end
end


## The parameters' values, then the boundary species' values, as a real
## vector in the order of parameter_names(model): the vector rhs(model) reads
## as its third argument. A boundary species with no assigned value is 0.
export function parameter_values(model)
  names = keys(model.parameters)
  p = zeros(length(names) + length(model.boundary))
  for i in 1:length(names)
    p[i] = model.parameters[names[i]]
  end
  k = length(names)
  for b in keys(model.boundary)
    k = k + 1
    v = model.boundary[b]
    if v != nothing
      p[k] = v
    end
  end
  return p
end


# Each rate law may use only species, parameters, boundary species and
# built-in functions; parse_function reports any other name with its
# position.
function check_rates(model)
  known = join(keys(model.species), ", ")
  pnames = parameter_names(model)
  if length(pnames) > 0
    if known != ""
      known = known + ", "
    end
    known = known + join(pnames, ", ")
  end
  for r in model.reactions
    try
      parse_function(known, r.rate)
    catch err
      error(err.kind, "rate law of reaction " + r.name + ": " + err.message)
    end
  end
end


# The first lines of the functions rhs_text and rates_text write: the header,
# the species, parameters and boundary species as local names set from _y
# and _p, and the rates _v1, _v2, ... of the reactions in order.
function rate_lines(model, header)
  check_rates(model)
  names = keys(model.species)
  pnames = parameter_names(model)
  lines = {header}
  for i in 1:length(names)
    lines = append(lines, "  " + names[i] + " = _y[" + string(i) + "]")
  end
  for i in 1:length(pnames)
    lines = append(lines, "  " + pnames[i] + " = _p[" + string(i) + "]")
  end
  for j in 1:length(model.reactions)
    lines = append(lines, "  _v" + string(j) + " = " + model.reactions[j].rate)
  end
  return lines
end


## The text of the function that rhs(model) makes, to read or check: the
## species, parameters and boundary species as local names set from _y and
## _p, the rates _v1, _v2, ... of the reactions in order, and the derivatives.
export function rhs_text(model)
  names = keys(model.species)
  lines = rate_lines(model, "function(_t, _y, _p)")

  # Row i of N v: the rates that change species i, with their coefficients.
  N = stoichiometry(model)
  rows = {}
  for i in 1:length(names)
    s = ""
    for j in 1:length(model.reactions)
      s = s + term(N[i, j], "_v" + string(j))
    end
    if s == ""
      s = "0.0"
    elseif startswith(s, " + ")
      s = s[4:end]
    else
      s = "-" + s[4:end]
    end
    rows = append(rows, s)
  end
  lines = append(lines, "  return [" + join(rows, "; ") + "]")
  lines = append(lines, "end")
  return join(lines, "\n")
end


## The right-hand side of the model's differential equations, dy/dt = N v(y),
## as a function f(t, y, p) for ode.solve with params = p: y holds the
## floating species in the order of species_names(model) and p the
## parameters' and boundary species' values, as parameter_values(model)
## gives them. The rate laws become one function made with parse_function,
## so they are checked here, and the JIT compiles it.
export function rhs(model)
  return parse_function(rhs_text(model))
end


## The reactions' names, in order: the columns of stoichiometry(model).
export function reaction_names(model)
  names = {}
  for r in model.reactions
    names = append(names, r.name)
  end
  return names
end


## The text of the function that rates(model) makes: as rhs_text, but taking
## (_y, _p) and returning the rates [_v1; _v2; ...] themselves.
export function rates_text(model)
  lines = rate_lines(model, "function(_y, _p)")
  vs = {}
  for j in 1:length(model.reactions)
    vs = append(vs, "_v" + string(j))
  end
  lines = append(lines, "  return [" + join(vs, "; ") + "]")
  lines = append(lines, "end")
  return join(lines, "\n")
end


## The reaction rates as a function v(y, p): y holds the floating species in
## the order of species_names(model) and p the values parameter_values(model)
## gives; the result is the vector of rates in the order of
## reaction_names(model). Compiled by the JIT, as rhs is.
export function rates(model)
  return parse_function(rates_text(model))
end


# y as a real vector.
function real_vector(y)
  return reshape([y] + 0.0, length([y]))
end


## The reaction rates at the floating species' values y, with the model's
## parameter and boundary values: the fluxes, when y is a steady state.
export function fluxes(model, y)
  if length(model.reactions) == 0
    return zeros(0)
  end
  return real_vector(rates(model)(real_vector(y), parameter_values(model)))
end


# ------------------------------------------------------------ simulating

## Simulates the model from t_start to t_end and returns ode.solve's result,
## reported at `points` evenly spaced times, with the species names as its
## names: sol.y[i, :] is species i over time. method is "rk45" or "bdf"
## (for stiff models).
export function simulate(model, t_end; t_start = 0.0, points = 101, method = "rk45",
                         rtol = 1e-6, atol = 1e-9)
  return ode.solve(rhs(model), initial(model), [t_start, t_end], method = method,
                   rtol = rtol, atol = atol, params = parameter_values(model),
                   t_eval = linspace(t_start, t_end, points),
                   names = species_names(model))
end


## A simulation to advance in steps with step(sim, h), changing species or
## parameters between steps with set(sim, name, value). The model is made
## into code once, here, and the solver keeps its state from step to step,
## starting afresh only after a change. A record with fields t (the time,
## from t_start), y (the floating species' values), p (the parameters' and
## boundary species' values), species and parameters (their names, in the
## order of y and p) and solver (an ode.integrator).
export function simulator(model; t_start = 0.0, method = "rk45", rtol = 1e-6, atol = 1e-9)
  return {t: t_start + 0.0, y: initial(model), p: parameter_values(model),
          species: species_names(model), parameters: parameter_names(model),
          solver: ode.integrator(rhs(model), method = method, rtol = rtol, atol = atol)}
end


## sim advanced by h > 0 in time: the same record with t and y at the new
## time. The solver continues from the previous step unless a value was
## changed, so many short steps cost about what one simulation does.
export function step(sim, h)
  target = sim.t + h
  sim.y = ode.advance(sim.solver, sim.t, sim.y, target, params = sim.p)
  sim.t = target
  return sim
end


# The position of name in names, or 0.
function position(names, name)
  for i in 1:length(names)
    if names[i] == name
      return i
    end
  end
  return 0
end


## sim with the species, parameter or boundary species called name set to
## value, from the next step on.
export function set(sim, name, value)
  i = position(sim.species, name)
  if i > 0
    sim.y[i] = value
    return sim
  end
  i = position(sim.parameters, name)
  if i > 0
    sim.p[i] = value
    return sim
  end
  error("NameError", "antimony.set: the model has no species or parameter \"" + name + "\"")
end


## The value of the species, parameter or boundary species called name in sim.
export function value(sim, name)
  i = position(sim.species, name)
  if i > 0
    return sim.y[i]
  end
  i = position(sim.parameters, name)
  if i > 0
    return sim.p[i]
  end
  error("NameError", "antimony.value: the model has no species or parameter \"" + name + "\"")
end


# ------------------------------------------------------------ conservation

## The conservation analysis of a model's stoichiometry matrix N (Reder 1988;
## Sauro and Ingalls 2004; Vallabhajosyula, Chickarmane and Sauro 2006).
## Rows of N that are combinations of other rows are dependent species, whose
## values follow from the independent species and a conserved total. The
## fields: independent and dependent (the species' names), ind and dep (their
## positions in species_names(model)), Nr (the reduced stoichiometry: N's
## rows for the independent species, in the order of independent), L0 (the
## dependent rows in terms of Nr: N[dep, :] = L0 * Nr), link (the link
## matrix, one row per species in species_names order: N = link * Nr) and
## gamma (the conservation matrix: one row per conserved total, one column
## per species, gamma * N = 0, so gamma * y stays at gamma * y0).
export record Conservation
  independent: list
  dependent: list
  ind: vector
  dep: vector
  Nr: matrix
  L0: matrix
  link: matrix
  gamma: matrix
end

EPS = 2.220446049250313e-16

# x, with entries within 1e-10 of a whole number made that number: L0 is
# computed in floating point, but its entries are usually small integers.
function clean(M)
  for i in 1:size(M, 1)
    for j in 1:size(M, 2)
      if abs(M[i, j] - round(M[i, j])) < 1e-10
        M[i, j] = round(M[i, j]) + 0.0
      end
    end
  end
  return M
end

## The model's conservation analysis, as a Conservation record. The
## independent species are chosen by QR factorisation of N' with column
## pivoting (linalg.qrp): the species whose rows of N are taken first, largest
## first, up to the rank of N. Both lists are in the order of species_names.
export function conservation(model)
  names = species_names(model)
  N = stoichiometry(model)
  [m, r] = size(N)
  rank = 0
  if r > 0
    [Q, R, p] = linalg.qrp(N')
    k = min(r, m)
    big = 0.0
    if k > 0 big = abs(R[1, 1]) end
    tol = max(m, r) * EPS * big
    while rank < k and abs(R[rank + 1, rank + 1]) > tol
      rank = rank + 1
    end
  else
    p = 1:m
  end
  ind = p[1:rank]
  dep = p[(rank + 1):m]
  c = m - rank
  # With N' P = Q R: N's independent rows are R11' Q1' and its dependent
  # rows R12' Q1', so N[dep, :] = (R11 \ R12)' * N[ind, :].
  if rank > 0 and c > 0
    L0 = clean((R[1:rank, 1:rank] \ R[1:rank, (rank + 1):m])')
  else
    L0 = zeros(c, rank)
  end
  # The same species, listed in the model's order (L0's columns and rows follow).
  if rank > 0
    order = sortperm(ind)
    ind = ind[order]
    L0 = L0[:, order]
  end
  if c > 0
    order = sortperm(dep)
    dep = dep[order]
    L0 = L0[order, :]
  end
  link = zeros(m, rank)
  link[ind, :] = eye(rank)
  link[dep, :] = L0
  gamma = zeros(c, m)
  gamma[:, dep] = eye(c)
  gamma[:, ind] = 0.0 - L0          # not -L0, which would show zeros as -0.0
  independent = {}
  for i in ind
    independent = append(independent, names[i])
  end
  dependent = {}
  for i in dep
    dependent = append(dependent, names[i])
  end
  return Conservation(independent, dependent, int(ind), int(dep), N[ind, :], L0, link,
                      gamma)
end


# ------------------------------------------------------------ steady state

## The model's steady state: species values y at which dy/dt = N v(y) = 0,
## found with nonlin.solve from guess (by default the initial values).
## Totals that the reactions conserve, such as A + B when A -> B and B -> A
## are the only reactions, keep the values they have in initial(model).
## method "reduced" (the default) solves for the independent species of
## conservation(model) only, with the dependent ones following from the
## totals; method "augmented" solves for every species, with the residual
## N v(y) + K (K' y - K' y0), K = linalg.null(N'), which is zero exactly when
## the rates balance and the totals keep their values. Returns a record with
## y, species (their names, in the order of y), status, fnorm, nfev and
## niters, as nonlin.solve reports them.
export function steady_state(model; guess = nothing, method = "reduced", ftol = 1e-10,
                             max_iters = 200)
  f = rhs(model)
  y0 = initial(model)
  p = parameter_values(model)
  if typeof(guess) == "nothing"
    guess = y0
  end
  if method == "augmented"
    K = linalg.null(stoichiometry(model)')       # orthonormal; K' N = 0
    totals = K' * y0
    residual = function(y, p) return f(0.0, y, p) + K * (K' * y - totals) end
    r = nonlin.solve(residual, guess, params = p, ftol = ftol, max_iters = max_iters)
    y = r.x
  elseif method == "reduced"
    cons = conservation(model)
    totals = cons.gamma * y0
    if length(cons.ind) == 0
      # Nothing changes: every species is fixed by a total.
      return {y: y0, species: species_names(model), status: "success", fnorm: 0.0,
              nfev: 0, niters: 0}
    end
    # The species' values from the independent ones: y[dep] = L0 y[ind] + totals.
    full = function(yi)
      ys = zeros(length(y0))
      ys[cons.ind] = yi
      ys[cons.dep] = cons.L0 * yi + totals
      return ys
    end
    residual = function(yi, p) return f(0.0, full(yi), p)[cons.ind] end
    r = nonlin.solve(residual, guess[cons.ind], params = p, ftol = ftol,
                     max_iters = max_iters)
    y = full(r.x)
  else
    error("ArgumentError", "antimony.steady_state: method must be \"reduced\" or \"augmented\", got \"" +
      string(method) + "\"")
  end
  return {y: y, species: species_names(model), status: r.status, fnorm: r.fnorm,
          nfev: r.nfev, niters: r.niters}
end


# ------------------------------------------------------------ Jacobians

## The Jacobian of dy/dt = N v(y) at the species' values y (a vector in the
## order of species_names(model)), with the model's parameter values:
## J[i, j] is the derivative of dy_i/dt with respect to y_j, by central
## differences. With conserved totals it is singular.
export function jacobian(model, y)
  f = rhs(model)
  p = parameter_values(model)
  y = reshape([y] + 0.0, length([y]))
  m = length(y)
  J = zeros(m, m)
  for j in 1:m
    h = 6.0554544523933395e-6 * max(abs(y[j]), 1.0)     # eps^(1/3), scaled
    up = y
    up[j] = y[j] + h
    down = y
    down[j] = y[j] - h
    J[:, j] = (f(0.0, up, p) - f(0.0, down, p)) / (up[j] - down[j])
  end
  return J
end

## The reduced Jacobian at y: the derivatives of the independent species'
## rates of change with respect to the independent species, the dependent ones
## following through the conserved totals, Nr (dv/dy) link. Rows and columns
## are in the order of conservation(model).independent. Its eigenvalues decide
## whether a steady state is stable: all with negative real parts.
export function reduced_jacobian(model, y)
  cons = conservation(model)
  return jacobian(model, y)[cons.ind, :] * cons.link
end


# ------------------------------------------------------------ control analysis

NAN = 0.0 / 0.0

# y as a real vector of the floating species' values, checked against the
# model.
function species_values(model, y, where)
  t = typeof(y)
  if t != "vector" and t != "matrix" and t != "real" and t != "int"
    error("TypeError", where + ": y must be a real vector, got " + t)
  end
  y = real_vector(y)
  if length(y) != length(model.species)
    error("DimensionError", where + ": y has " + string(length(y)) +
      " values but the model has " + string(length(model.species)) + " floating species")
  end
  return y
end

# The derivatives of the rates v(y, p) with respect to each entry of y (by =
# "species") or of p (by = "parameters"): one row per reaction, one column
# per entry. Five-point differences, as libRoadRunner computes them:
# (v(x - 2h) - 8 v(x - h) + 8 v(x + h) - v(x + 2h)) / 12h, with h relative to
# the entry (eps^(1/5) |x|, or eps^(1/5) 1e-6 for an entry of 0); the error
# is of order h^4.
function rate_derivatives(model, y, by)
  p = parameter_values(model)
  x = p
  if by == "species" x = y end
  n = length(model.reactions)
  D = zeros(n, length(x))
  if n == 0 or length(x) == 0
    return D
  end
  v = rates(model)
  for j in 1:length(x)
    h = 7.40095979741405e-4 * max(abs(x[j]), 1e-6)
    h = (x[j] + h) - x[j]          # a step that x[j] + h represents exactly
    f = zeros(n, 4)
    k = 0
    for s in {-2.0, -1.0, 1.0, 2.0}
      k = k + 1
      xs = x
      xs[j] = x[j] + s * h
      if by == "species"
        f[:, k] = real_vector(v(xs, p))
      else
        f[:, k] = real_vector(v(y, xs))
      end
    end
    D[:, j] = (f[:, 1] - 8 * f[:, 2] + 8 * f[:, 3] - f[:, 4]) / (12 * h)
  end
  return D
end

# M scaled: M[i, j] col[j] / row[i], NaN where row[i] is 0.
function scale(M, row, col)
  [m, n] = size(M)
  S = zeros(m, n)
  for i in 1:m
    for j in 1:n
      if row[i] == 0
        S[i, j] = NAN
      else
        S[i, j] = M[i, j] * col[j] / row[i]
      end
    end
  end
  return S
end

## The elasticities of the reactions with respect to the floating species at
## the species' values y: E[i, j] is the derivative of reaction i's rate
## with respect to species j (rows in the order of reaction_names, columns in
## the order of species_names), by five-point differences, as libRoadRunner
## computes them. scaled = true gives the scaled elasticities
## E[i, j] y[j] / v[i] instead (NaN where the rate v[i] is 0).
export function elasticities(model, y; scaled = false)
  y = species_values(model, y, "antimony.elasticities")
  E = rate_derivatives(model, y, "species")
  if scaled
    E = scale(E, fluxes(model, y), y)
  end
  return E
end

## The elasticities of the reactions with respect to the parameters, then the
## boundary species (the columns in the order of parameter_names), at the
## floating species' values y. scaled = true gives E[i, k] p[k] / v[i].
export function parameter_elasticities(model, y; scaled = false)
  y = species_values(model, y, "antimony.parameter_elasticities")
  E = rate_derivatives(model, y, "parameters")
  if scaled
    E = scale(E, fluxes(model, y), parameter_values(model))
  end
  return E
end

## The result of control(model): the floating species and the reactions, the
## steady state y and its fluxes J (J[i] is reaction i's rate), the
## elasticities (reactions × species), the flux control coefficients
## (flux_control[i, j]: of the flux through reaction i by reaction j) and the
## concentration control coefficients (concentration_control[i, j]: of
## species i by reaction j). All scaled when scaled is true.
export record Control
  species: list
  reactions: list
  y: vector
  J: vector
  elasticities: matrix
  flux_control: matrix
  concentration_control: matrix
  scaled: bool
end

## Metabolic control analysis of the model at a steady state: a Control
## record. y is the steady state (the floating species' values); by default
## it is found with steady_state(model). With the elasticities E (unscaled),
## the reduced stoichiometry Nr and link matrix L of conservation(model), the
## reduced Jacobian Jr = Nr E L gives the concentration control coefficients
## Cs = -L Jr^-1 Nr and the flux control coefficients CJ = I + E Cs (Reder
## 1988), which hold with conserved moieties, branches and cycles. Scaled
## (the default): CJ[i, j] J[j] / J[i] and Cs[i, j] J[j] / y[i], NaN where
## the flux or concentration divided by is 0. Each row of the scaled flux
## control coefficients sums to 1 and of the concentration ones to 0.
export function control(model; y = nothing, scaled = true)
  c = unscaled_control(model, y, "antimony.control")
  if scaled
    return Control(species_names(model), reaction_names(model), c.y, c.J,
                   scale(c.E, c.J, c.y), scale(c.CJ, c.J, c.J), scale(c.Cs, c.y, c.J), true)
  end
  return Control(species_names(model), reaction_names(model), c.y, c.J, c.E, c.CJ, c.Cs,
                 false)
end

# The steady state (y, or steady_state(model) when y is nothing), its fluxes
# J, the unscaled elasticities E and control coefficients CJ and Cs.
function unscaled_control(model, y, where)
  if typeof(y) == "nothing"
    ss = steady_state(model)
    if ss.status != "success"
      error("ArgumentError", where + ": the steady state was not found (status " +
        ss.status + ", |f| = " + string(ss.fnorm) + "); give it as y")
    end
    y = ss.y
  end
  y = species_values(model, y, where)
  E = rate_derivatives(model, y, "species")
  J = fluxes(model, y)
  cons = conservation(model)
  m = length(y)
  n = length(J)
  Cs = zeros(m, n)
  if length(cons.ind) > 0
    Jr = cons.Nr * E * cons.link
    try
      Cs = 0.0 - cons.link * (Jr \ cons.Nr)
    catch err
      if err.kind == "SingularMatrix"
        error("SingularMatrix", where + ": the reduced Jacobian is singular at " +
          "this point, so the control coefficients are not defined")
      end
      error(err.kind, err.message)
    end
  end
  return {y: y, J: J, E: E, CJ: eye(n) + E * Cs, Cs: Cs}
end

## The result of response(model): the parameters (the parameters, then the
## boundary species, as parameter_names gives them: the columns of both
## matrices), the floating species and the reactions (the rows of
## concentration and of flux), the steady state y and its fluxes J, and the
## response coefficients: flux[i, k] of the flux through reaction i to
## parameter k, concentration[i, k] of species i to parameter k. Scaled when
## scaled is true.
export record Response
  parameters: list
  species: list
  reactions: list
  y: vector
  J: vector
  flux: matrix
  concentration: matrix
  scaled: bool
end

## The response coefficients of the steady state to every parameter and
## boundary species, as a Response record: how the fluxes and concentrations
## change with each. y is the steady state, by default steady_state(model).
## They are the control coefficients times the parameter elasticities P:
## R^J = CJ P and R^S = Cs P (unscaled). Scaled (the default): R^J[i, k]
## p[k] / J[i] and R^S[i, k] p[k] / y[i], NaN where the value divided by is 0.
export function response(model; y = nothing, scaled = true)
  c = unscaled_control(model, y, "antimony.response")
  P = rate_derivatives(model, c.y, "parameters")
  RJ = c.CJ * P
  RS = c.Cs * P
  if scaled
    p = parameter_values(model)
    RJ = scale(RJ, c.J, p)
    RS = scale(RS, c.y, p)
  end
  return Response(parameter_names(model), species_names(model), reaction_names(model), c.y,
                  c.J, RJ, RS, scaled)
end
