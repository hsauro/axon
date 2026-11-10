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
## parameters. simulate solves a whole time span; simulator, step and set
## advance a simulation in steps, changing values between them. See the
## Language Reference, "The antimony module".

import io
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

## A model: its reactions in order, its species (name to initial value, or
## nothing when none was assigned) in the order they first appear, and its
## parameters (name to value) in the order they were assigned.
export record Model
  reactions: list
  species: dict
  parameters: dict
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
  species = dict()
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
      reactants = parse_side(sides[1])
      products = parse_side(sides[2])
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
      values[trim(parts[1])] = read_number(trim(parts[2]))
    end

    i = i + 1
  end

  # Assignments may come before or after the reactions that use a name.
  parameters = dict()
  for name in keys(values)
    if haskey(species, name)
      species[name] = values[name]
    else
      parameters[name] = values[name]
    end
  end

  return Model(reactions, species, parameters)
end


## The model in the file at path.
export function read(path)
  return load(io.read_file(path))
end


# ------------------------------------------------------------ analysis

## The species names, in the order of the rows of stoichiometry(model) and
## the components of a simulation.
export function species_names(model)
  return keys(model.species)
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


## The parameters' values as a real vector, in the order of
## keys(model.parameters): the vector rhs(model) reads as its third argument.
export function parameter_values(model)
  names = keys(model.parameters)
  p = zeros(length(names))
  for i in 1:length(names)
    p[i] = model.parameters[names[i]]
  end
  return p
end


# Each rate law may use only species, parameters and built-in functions;
# parse_function reports any other name with its position.
function check_rates(model)
  known = join(keys(model.species), ", ")
  if length(model.parameters) > 0
    known = known + ", " + join(keys(model.parameters), ", ")
  end
  for r in model.reactions
    try
      parse_function(known, r.rate)
    catch err
      error(err.kind, "rate law of reaction " + r.name + ": " + err.message)
    end
  end
end


## The text of the function that rhs(model) makes, to read or check: the
## species and parameters as local names set from _y and _p, the rates _v1,
## _v2, ... of the reactions in order, and the derivatives.
export function rhs_text(model)
  check_rates(model)
  names = keys(model.species)
  pnames = keys(model.parameters)
  lines = {"function(_t, _y, _p)"}
  for i in 1:length(names)
    lines = append(lines, "  " + names[i] + " = _y[" + string(i) + "]")
  end
  for i in 1:length(pnames)
    lines = append(lines, "  " + pnames[i] + " = _p[" + string(i) + "]")
  end
  for j in 1:length(model.reactions)
    lines = append(lines, "  _v" + string(j) + " = " + model.reactions[j].rate)
  end

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
## species in the order of species_names(model) and p the parameters'
## values, as parameter_values(model) gives them. The rate laws become one
## function made with parse_function, so they are checked here, and the JIT
## compiles it.
export function rhs(model)
  return parse_function(rhs_text(model))
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
## from t_start), y (the species' values), p (the parameters' values),
## species and parameters (their names, in the order of y and p) and solver
## (an ode.integrator).
export function simulator(model; t_start = 0.0, method = "rk45", rtol = 1e-6, atol = 1e-9)
  return {t: t_start + 0.0, y: initial(model), p: parameter_values(model),
          species: species_names(model), parameters: keys(model.parameters),
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


## sim with the species or parameter called name set to value, from the next
## step on.
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


## The value of the species or parameter called name in sim.
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
