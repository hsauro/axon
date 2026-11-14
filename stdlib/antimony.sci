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
## so the species that change are the floating ones. Compartments, species
## declarations and assignment rules are read too:
##   compartment cell, outside; cell = 1; outside = 100
##   species S1 in cell, $X0 in outside
##   MgATP := MG*ATP/(Kd + MG)    # recomputed whenever the rates are
## A rate law gives an amount per unit time, so a species' concentration
## changes by its share of N v divided by its compartment's size.
## simulate solves a whole time span; simulator, step and set advance a
## simulation in steps, changing values between them; steady_state finds
## where the species stop changing; conservation and kernel find the
## conservation laws and how the steady-state fluxes depend on each other;
## control and response give the control and response coefficients. See the
## Language Reference, "The antimony module".

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
## value, or nothing when none was assigned) in the order they are first
## declared or used, its parameters (name to value) in the order they were
## assigned, its boundary species ($X: name to value, or nothing), which stay
## fixed, its compartments (name to size, nothing for 1), the compartment of
## each species declared in one (species_in: species name to compartment
## name), and its assignment rules (rules: name to the expression, as
## written, that gives its value).
export record Model
  reactions: list
  species: dict
  parameters: dict
  boundary: dict
  compartments: dict
  species_in: dict
  rules: dict
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


# A declared compartment, "name" or "name = size": its name and size
# (nothing when none is given).
function declared(item, statement)
  parts = split(item, "=")
  name = trim(parts[1])
  if name == "" or length(parts) > 2 or length(split(name)) != 1
    error("Invalid declaration: " + statement)
  end
  if length(parts) == 2
    return name, read_number(trim(parts[2]))
  end
  return name, nothing
end


## The model in the text source.
export function load(source)
  statements = statements_of(source)
  reactions = {}
  species = dict()       # every species, declared or in a reaction, in order
  reacting = dict()      # the names that take part in a reaction
  boundary = dict()      # the names marked with "$" anywhere
  compartments = dict()  # name to size (nothing: 1)
  species_in = dict()    # species to compartment
  rules = dict()         # name to expression
  values = dict()        # every assignment; sorted out at the end
  unnamed = 0            # reactions given no name so far

  i = 1
  while i <= length(statements)
    statement = statements[i]
    arrow = arrow_of(statement)
    first = split(statement)[1]

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
          reacting[s] = true
        end
      end

      # The rate law is the next statement.
      i = i + 1
      if i > length(statements)
        error("Missing rate law for reaction: " + statement)
      end
      reactions = append(reactions, Reaction(name, reactants, products, statements[i]))
    elseif first == "compartment"
      # compartment cell, outside = 100
      for item in split(trim(statement[12:end]), ",")
        [name, size] = declared(item, statement)
        compartments[name] = nothing
        if size != nothing
          values[name] = size
        end
      end
    elseif first == "species"
      # species A in cell, $B in cell, C
      for item in split(trim(statement[8:end]), ",")
        words = split(trim(item))
        place = nothing
        if length(words) == 3 and words[2] == "in"
          place = words[3]
        elseif length(words) != 1
          error("Invalid species declaration: " + statement)
        end
        name = words[1]
        if startswith(name, "$")
          name = trim(name[2:end])
          boundary[name] = nothing
        end
        if name == ""
          error("Invalid species declaration: " + statement)
        end
        species[name] = nothing
        if place != nothing
          species_in[name] = place
          if not haskey(compartments, place)
            compartments[place] = nothing
          end
        end
      end
    elseif contains(statement, ":=")
      # An assignment rule, name := expression.
      k = find(statement, ":=")
      name = trim(statement[1:k - 1])
      if startswith(name, "$")
        name = trim(name[2:end])
        boundary[name] = nothing
      end
      expr = trim(statement[k + 2:end])
      if name == "" or expr == "" or length(split(name)) != 1
        error("Invalid assignment rule: " + statement)
      end
      rules[name] = expr
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
  # a name with a rule is computed, so it is neither a species that changes
  # nor a value of its own.
  for name in keys(rules)
    if haskey(reacting, name) and not haskey(boundary, name)
      error("ArgumentError", "species " + name + " has an assignment rule but changes in " +
        "a reaction; mark it $" + name + " (a boundary species)")
    end
    if haskey(compartments, name)
      error("ArgumentError", "the size of compartment " + name +
        " is given by a rule, which is not read")
    end
  end
  floating = dict()
  for name in keys(species)
    if not haskey(boundary, name) and not haskey(rules, name)
      floating[name] = nothing
    end
  end
  fixed = dict()
  for name in keys(boundary)
    if not haskey(rules, name)
      fixed[name] = nothing
    end
  end

  # Assignments may come before or after the reactions that use a name. A
  # value for a name with a rule would only be where it starts; the rule
  # decides, so it is left out.
  parameters = dict()
  for name in keys(values)
    if haskey(rules, name)
      # computed
    elseif haskey(floating, name)
      floating[name] = values[name]
    elseif haskey(fixed, name)
      fixed[name] = values[name]
    elseif haskey(compartments, name)
      compartments[name] = values[name]
    else
      parameters[name] = values[name]
    end
  end

  return Model(reactions, floating, parameters, fixed, compartments, species_in, rules)
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
## the boundary species, then the compartments.
export function parameter_names(model)
  names = keys(model.parameters)
  for b in keys(model.boundary)
    names = append(names, b)
  end
  for c in keys(model.compartments)
    names = append(names, c)
  end
  return names
end


## The size of each floating species' compartment, in the order of
## species_names (1 for a species in no compartment, or in one whose size was
## never assigned): a species' concentration changes at its row of N v
## divided by it.
export function volumes(model)
  names = keys(model.species)
  v = ones(length(names))
  for i in 1:length(names)
    if haskey(model.species_in, names[i])
      size = model.compartments[model.species_in[names[i]]]
      if size != nothing
        v[i] = size
      end
    end
  end
  return v
end


# The stoichiometry matrix with each species' row divided by its
# compartment's size: dy/dt = (this) v for the concentrations y. Its
# conservation laws hold for concentrations.
function scaled_stoichiometry(model)
  N = stoichiometry(model)
  v = volumes(model)
  for i in 1:length(v)
    if v[i] != 1
      N[i, :] = N[i, :] / v[i]
    end
  end
  return N
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


## The parameters' values, then the boundary species' values, then the
## compartments' sizes, as a real vector in the order of
## parameter_names(model): the vector rhs(model) reads as its third
## argument. A boundary species with no assigned value is 0, a compartment
## with no size 1.
export function parameter_values(model)
  names = keys(model.parameters)
  p = zeros(length(names) + length(model.boundary) + length(model.compartments))
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
  for c in keys(model.compartments)
    k = k + 1
    v = model.compartments[c]
    if v == nothing
      v = 1
    end
    p[k] = v
  end
  return p
end


# Each rate law may use only species, parameters, boundary species and
# built-in functions; parse_function reports any other name with its
# position.
function check_rates(model)
  names = keys(model.species)
  for n in parameter_names(model)
    names = append(names, n)
  end
  for n in keys(model.rules)
    names = append(names, n)
  end
  known = join(names, ", ")
  for n in keys(model.rules)
    try
      parse_function(known, translate(model.rules[n]))
    catch err
      error(err.kind, "assignment rule for " + n + ": " + err.message)
    end
  end
  for r in model.reactions
    try
      parse_function(known, translate(r.rate))
    catch err
      error(err.kind, "rate law of reaction " + r.name + ": " + err.message)
    end
  end
end


# Whether c, one character, can start a name, or is a digit.
function is_letter(c)
  return ("a" <= c and c <= "z") or ("A" <= c and c <= "Z") or c == "_"
end
function is_digit(c)
  return "0" <= c and c <= "9"
end

# An expression's text in pieces: names, numbers (with an exponent) and the
# characters between them, which join back to the text.
function pieces(expr)
  result = {}
  n = length(expr)
  i = 1
  while i <= n
    c = expr[i]
    j = i
    if is_letter(c)
      while j < n and (is_letter(expr[j + 1]) or is_digit(expr[j + 1]))
        j = j + 1
      end
    elseif is_digit(c) or (c == "." and i < n and is_digit(expr[i + 1]))
      while j < n and (is_digit(expr[j + 1]) or expr[j + 1] == ".")
        j = j + 1
      end
      if j < n and (expr[j + 1] == "e" or expr[j + 1] == "E")
        k = j + 2
        if k <= n and (expr[k] == "+" or expr[k] == "-")
          k = k + 1
        end
        if k <= n and is_digit(expr[k])
          j = k
          while j < n and is_digit(expr[j + 1])
            j = j + 1
          end
        end
      end
    end
    result = append(result, expr[i:j])
    i = j + 1
  end
  return result
end

# The names an expression uses.
function names_in(expr)
  result = {}
  for piece in pieces(expr)
    if is_letter(piece[1])
      result = append(result, piece)
    end
  end
  return result
end

# A rate law or rule as Axon code: Antimony's ln is Axon's log (Antimony's
# log is the natural logarithm too).
function translate(expr)
  if find(expr, "ln") == 0
    return expr
  end
  ps = pieces(expr)
  for k in 1:length(ps)
    if ps[k] == "ln"
      ps[k] = "log"
    end
  end
  return join(ps, "")
end

# The rules' names in an order in which each comes after the rules it uses.
function ordered_rules(model)
  names = keys(model.rules)
  uses = dict()
  for n in names
    deps = {}
    for t in names_in(model.rules[n])
      if haskey(model.rules, t) and t != n
        deps = append(deps, t)
      end
    end
    uses[n] = deps
  end
  done = dict()
  order = {}
  while length(order) < length(names)
    progress = false
    for n in names
      if not haskey(done, n)
        ready = true
        for d in uses[n]
          if not haskey(done, d)
            ready = false
          end
        end
        if ready
          order = append(order, n)
          done[n] = true
          progress = true
        end
      end
    end
    if not progress
      left = {}
      for n in names
        if not haskey(done, n)
          left = append(left, n)
        end
      end
      error("ArgumentError", "the assignment rules for " + join(left, ", ") +
        " depend on each other in a cycle")
    end
  end
  return order
end


# The first lines of the functions rhs_text and rates_text write: the header,
# the species, parameters, boundary species and compartments as local names
# set from _y and _p, the assignment rules (each after those it uses), and
# the rates _v1, _v2, ... of the reactions in order.
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
  for n in ordered_rules(model)
    lines = append(lines, "  " + n + " = " + translate(model.rules[n]))
  end
  for j in 1:length(model.reactions)
    lines = append(lines, "  _v" + string(j) + " = " + translate(model.reactions[j].rate))
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
    # Rates are amounts per unit time: a concentration changes by the
    # amount over its compartment's size.
    if s != "0.0" and haskey(model.species_in, names[i])
      s = "(" + s + ")/" + model.species_in[names[i]]
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
## conservation(N) analyses a stoichiometry matrix N itself, whose species
## are then named S1, S2, ... in the order of its rows.
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

# The stoichiometry matrix that conservation and kernel analyse, the names
# of its rows and the names of its columns: a model's (each species' row
# divided by its compartment's size when scaled is true), or a matrix given
# as it is (a vector is one column), its rows named S1, S2, ... and its
# columns J1, J2, ...
function structure_of(x, scaled, where)
  t = typeof(x)
  if t == "Model"
    if scaled
      N = scaled_stoichiometry(x)
    else
      N = stoichiometry(x)
    end
    return N, species_names(x), reaction_names(x)
  end
  if t == "matrix"
    N = x + 0.0
  elseif t == "vector"
    N = reshape(x + 0.0, length(x), 1)
  else
    error("ArgumentError", where + ": expected a model or a stoichiometry matrix, got " + t)
  end
  return N, numbered("S", size(N, 1)), numbered("J", size(N, 2))
end

# The list of names prefix + "1" to prefix + string(n).
function numbered(prefix, n)
  names = {}
  for i in 1:n
    names = append(names, prefix + string(i))
  end
  return names
end

# The columns of A in the order QR factorisation with column pivoting takes
# them (linalg.qrp: A[:, p] = Q * R, largest first), A's rank (the number of
# R's diagonal entries larger than max(size(A)) eps |R[1, 1]|) and R. The
# columns p[1:rank] are linearly independent and the others combinations of
# them.
function pivot_columns(A)
  [m, n] = size(A)
  if m == 0 or n == 0
    return int(1:n), 0, zeros(0, n)
  end
  [Q, R, p] = linalg.qrp(A)
  k = min(m, n)
  tol = max(m, n) * EPS * abs(R[1, 1])
  rank = 0
  while rank < k and abs(R[rank + 1, rank + 1]) > tol
    rank = rank + 1
  end
  return p, rank, R
end

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
## model may also be a stoichiometry matrix (species by reactions).
export function conservation(model)
  [N, names, reactions] = structure_of(model, true, "antimony.conservation")
  m = size(N, 1)
  [p, rank, R] = pivot_columns(N')
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

## The kernel analysis of a model's stoichiometry matrix N (Reder 1988): the
## flux vectors J with N J = 0, the fluxes a steady state can have, written
## in terms of independent fluxes. The fields: independent and dependent
## (the reactions' names), ind and dep (their positions in
## reaction_names(model)), K0 (the dependent fluxes in terms of the
## independent ones: J[dep] = K0 * J[ind]) and K (the kernel matrix, one row
## per reaction in reaction_names order and one column per independent
## flux: N * K = 0, K[ind, :] the identity and K[dep, :] = K0, so
## J = K * J[ind]).
export record Kernel
  independent: list
  dependent: list
  ind: vector
  dep: vector
  K0: matrix
  K: matrix
end

## The model's kernel analysis, as a Kernel record. The dependent reactions
## are chosen by QR factorisation of N with column pivoting (linalg.qrp):
## the reactions whose columns of N are taken first, largest first, up to
## the rank of N; the fluxes of the others are independent. Both lists are
## in the order of reaction_names. Compartment sizes do not change the
## kernel, so N is stoichiometry(model). model may also be a stoichiometry
## matrix, whose reactions are then named J1, J2, ... in the order of its
## columns.
export function kernel(model)
  [N, species, names] = structure_of(model, false, "antimony.kernel")
  n = size(N, 2)
  [p, rank, R] = pivot_columns(N)
  dep = p[1:rank]
  ind = p[(rank + 1):n]
  f = n - rank
  # With N P = Q R: N[:, dep] = Q1 R11 and N[:, ind] = Q1 R12, so
  # N J = Q1 (R11 J[dep] + R12 J[ind]) = 0 when J[dep] = -(R11 \ R12) J[ind].
  if rank > 0 and f > 0
    K0 = clean(0.0 - (R[1:rank, 1:rank] \ R[1:rank, (rank + 1):n]))
  else
    K0 = zeros(rank, f)
  end
  # The same reactions, listed in the model's order (K0's rows and columns follow).
  if f > 0
    order = sortperm(ind)
    ind = ind[order]
    K0 = K0[:, order]
  end
  if rank > 0
    order = sortperm(dep)
    dep = dep[order]
    K0 = K0[order, :]
  end
  K = zeros(n, f)
  K[ind, :] = eye(f)
  K[dep, :] = K0
  independent = {}
  for j in ind
    independent = append(independent, names[j])
  end
  dependent = {}
  for j in dep
    dependent = append(dependent, names[j])
  end
  return Kernel(independent, dependent, int(ind), int(dep), K0, K)
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
    K = linalg.null(scaled_stoichiometry(model)')   # orthonormal; K' N = 0
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
