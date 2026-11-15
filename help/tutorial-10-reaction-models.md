# Lesson 10: Reaction models

[Tutorial](tutorial.md)

A network of chemical reactions, such as a metabolic pathway, becomes a set
of differential equations: each species changes at the rate at which
reactions make it, minus the rate at which they use it up. Lesson 9 wrote
such equations by hand. For more than a few reactions that is slow and easy
to get wrong. Axon's `antimony` module reads a model written as a list of
reactions, in the Antimony language that systems biologists use, and builds
and solves the equations for you.

## A first model

Here are two reactions: A turns into B, and B is removed. Each is written
with a name, the reaction, and after a semicolon its *rate law*, the rate
at which it runs:

```axon
# first_model.sci: A turns into B, and B is removed
import antimony
import plot
model = antimony.load("""
  J1: A -> B; k1*A
  J2: B -> ; k2*B
  k1 = 0.5; k2 = 0.2
  A = 10; B = 0
""")
sol = antimony.simulate(model, 20)
for k in 1:length(sol.names)
  plot.line(sol.t, sol.y[k, :], label = sol.names[k])
end
plot.title("A to B")
plot.xlabel("time")
plot.ylabel("concentration")
plot.show()
println("A at the end:", format(sol.y[1, end], 4))
println("B at the end:", format(sol.y[2, end], 4))
```

```output
A at the end: 0.0005
B at the end: 0.3045
```

The model is text written between three double quotes, `"""`, which lets
text run over several lines. In it:

- `J1: A -> B; k1*A` is a reaction named J1 that turns one A into one B, at
  the rate k1 times the amount of A. `J2: B -> ; k2*B` has nothing after
  the arrow: B is removed.
- `k1 = 0.5; k2 = 0.2` gives values to the constants in the rate laws, the
  *parameters*; `A = 10; B = 0` gives the starting amounts of the
  *species*. A semicolon separates statements written on one line.

`antimony.load` reads the model, and `antimony.simulate(model, 20)`
solves it from time 0 to 20 with `ode.solve`, so the result has the
fields of Lesson 9: `sol.t`, `sol.y` and also `sol.names`, the names of the
species in the order of the rows of `sol.y`.

## What the module builds

The module turns the reactions into the differential equations of Lesson 9.
You can see them:

```axon
# inside.sci: the equations behind a model
import antimony
model = antimony.load("""
  J1: A -> B; k1*A
  J2: B -> ; k2*B
  k1 = 0.5; k2 = 0.2
  A = 10; B = 0
""")
println(antimony.species_names(model))
println(antimony.reaction_names(model))
println(antimony.stoichiometry(model))
println(antimony.rhs_text(model))
```

```output
{"A", "B"}
{"J1", "J2"}
2×2 matrix{real}
  -1.0   0.0
   1.0  -1.0
function(_t, _y, _p)
  A = _y[1]
  B = _y[2]
  k1 = _p[1]
  k2 = _p[2]
  _v1 = k1*A
  _v2 = k2*B
  return [-_v1; _v1 - _v2]
end
```

The *stoichiometry matrix* has a row for each species and a column for each
reaction: J1 uses one A (-1) and makes one B (+1), and J2 uses one B. The
function at the end is a rate function like those of Lesson 9, written by
the module: it computes each reaction's rate, `_v1` and `_v2`, and returns
the rate of change of A, minus `_v1`, and of B, `_v1` minus `_v2`.

## Sources and sinks

In a living cell a pathway is fed from outside and its product is carried
away, at levels the pathway itself does not change. A species written with
a `$` in front is a *boundary species*: it is held at its value instead of
being changed by the reactions. This pathway turns X0 into S1 and S2 and
finally into X1, with Michaelis-Menten rate laws for the last two steps:

```axon
# pathway.sci: a three-step pathway
import antimony
import plot
pathway = antimony.load("""
  J0: $X0 -> S1; v0
  J1: S1 -> S2; Vm1*S1/(Km1 + S1)
  J2: S2 -> $X1; Vm2*S2/(Km2 + S2)
  v0 = 2; Vm1 = 10; Km1 = 1; Vm2 = 6; Km2 = 2
  X0 = 1; X1 = 0
""")
sol = antimony.simulate(pathway, 10)
plot.line(sol.t, sol.y[1, :], label = "S1")
plot.line(sol.t, sol.y[2, :], label = "S2")
plot.title("A pathway approaching its steady state")
plot.xlabel("time")
plot.ylabel("concentration")
plot.show()
```

S1 and S2 rise and then level off. The pathway settles into a *steady
state*, in which every species is made exactly as fast as it is used.

## The steady state

`antimony.steady_state` finds the steady state directly, with the
`nonlin` solver of Lesson 8, without simulating to it:

```axon
# steady.sci: the pathway's steady state
import antimony
pathway = antimony.load("""
  J0: $X0 -> S1; v0
  J1: S1 -> S2; Vm1*S1/(Km1 + S1)
  J2: S2 -> $X1; Vm2*S2/(Km2 + S2)
  v0 = 2; Vm1 = 10; Km1 = 1; Vm2 = 6; Km2 = 2
  X0 = 1; X1 = 0
""")
s = antimony.steady_state(pathway)
println(s.status)
println(s.species)
println(s.y')
println("Fluxes:", antimony.fluxes(pathway, s.y)')
```

```output
success
{"S1", "S2"}
1×2 matrix{real}
  0.25  1.0
Fluxes: 1×3 matrix{real}
  2.0  2.0  2.0
```

`s.y` holds the steady-state concentrations, in the order of `s.species`.
The *fluxes* are the reactions' rates there: all three are 2, the rate at
which the first step feeds the pathway, because at steady state whatever
enters a chain of reactions must pass through every step of it.

## Changing a parameter during a simulation

`antimony.simulator` makes a simulation that you advance in steps with
`antimony.step`, changing values between steps with `antimony.set`. Here
the supply rate `v0` doubles at t = 15:

```axon
# doubling_supply.sci: a change in the middle of a simulation
import antimony
pathway = antimony.load("""
  J0: $X0 -> S1; v0
  J1: S1 -> S2; Vm1*S1/(Km1 + S1)
  J2: S2 -> $X1; Vm2*S2/(Km2 + S2)
  v0 = 2; Vm1 = 10; Km1 = 1; Vm2 = 6; Km2 = 2
  X0 = 1; X1 = 0
""")
sim = antimony.simulator(pathway)
for k in 1:3
  sim = antimony.step(sim, 5.0)
  println(sim.t, format(antimony.value(sim, "S2"), 3))
end
sim = antimony.set(sim, "v0", 4.0)
for k in 1:3
  sim = antimony.step(sim, 5.0)
  println(sim.t, format(antimony.value(sim, "S2"), 3))
end
```

```output
5.0 0.999
10.0 1.000
15.0 1.000
20.0 3.601
25.0 3.929
30.0 3.987
```

Each step returns the simulation advanced in time, which is stored back in
`sim`, as `append` results were in Lesson 7. `antimony.value` reads a
species or parameter. Doubling the supply quadruples S2 here: the last step
is close to its maximum rate, 6, and S2 must rise a long way to push 4
through it.

## Events

A model can also change itself as it runs. An *event* does something when
a condition becomes true: `E1: at (time > 10): k1 = 5` raises `k1` to 5 at
time 10. After `at` comes the condition, called the *trigger*, in
brackets; after the colon, one or more assignments separated by commas.

```axon
# event.sci: the supply raised at t = 10
import antimony
import plot
model = antimony.load("""
  J1: -> S1; k1
  J2: S1 -> ; k2*S1
  k1 = 1; k2 = 0.1; S1 = 0
  E1: at (time > 10): k1 = 5
""")
sol = antimony.simulate(model, 30)
plot.line(sol.t, sol.y[1, :])
plot.title("Supply raised at t = 10")
plot.xlabel("time")
plot.ylabel("S1")
plot.show()
println("E1 fired at t =", sol.t_events[1][1])
```

```output
E1 fired at t = 10.0
```

A trigger can test species too, as in `at (S1 > 2): S1 = 0`, which empties
S1 every time it rises past 2, and conditions can be combined with `&&`
(and) and `||` (or). An event fires when its trigger *becomes* true, and
again only after it has been false in between. `sol.t_events` lists, for
each event, the times at which it fired. In a simulation in steps, after
each `antimony.step`, `sim.fired` lists the events that fired during the
step.

## Models in files

A longer model is better kept in a file of its own, such as
`pathway.ant`, holding the same lines as the text between the triple
quotes. `antimony.read` reads it:

```text
pathway = antimony.read("pathway.ant")
```

Models from other software that uses Antimony, such as Tellurium, can be
read the same way, as long as they use the parts of the language the module
reads: reactions, rate laws, values, `$` boundary species, compartments and
assignment rules.

## Which step controls the flux?

A question that comes up with every pathway is which of its steps sets
the flux through it: speeding up which enzyme would speed up the pathway
most? *Metabolic control analysis* answers it with *flux control
coefficients*: the relative change in the flux for a small relative change
in the rate of one step. `antimony.control` computes them. This chain of
reversible reactions shares control among its steps:

```axon
# control.sci: flux control coefficients of a chain
import antimony
chain = antimony.load("""
  J1: $X0 -> S1; k1*X0 - k2*S1
  J2: S1 -> S2; k3*S1 - k4*S2
  J3: S2 -> $X1; k5*S2
  k1 = 1; k2 = 0.5; k3 = 2; k4 = 1; k5 = 3
  X0 = 10; X1 = 0
""")
c = antimony.control(chain)
for j in 1:3
  println(c.reactions[j], format(c.flux_control[3, j], 3))
end
println("Sum:", format(sum(c.flux_control[3, :]), 3))
```

```output
J1 0.750
J2 0.188
J3 0.063
Sum: 1.000
```

Row 3 of `c.flux_control` is the control of the flux through the last
step by each of the three steps. The first step has most control, and the
coefficients add up to 1, which is always so: control is shared out, never
created. The manual's chapter on reaction models goes further.

## Mistakes

A rate law that uses a name with no value stops the simulation with a
`NameError` that names the reaction and the name, such as
`NameError: rate law of reaction J1: ... unknown name "k"`. Give every
parameter a value.

A species with no value starts at 0, without a warning. If a species
stays at zero when it should not, check that it was given a value.

## Summary

- A model is a list of reactions, `name: reactants -> products; rate law`,
  followed by values for the parameters and the starting amounts of the
  species. Text between `"""` can run over several lines.
- `antimony.load` reads a model from text, and `antimony.read` from a
  file.
- `antimony.simulate(model, t_end)` solves a model; `sol.names` names the
  rows of `sol.y`.
- `$X` marks a boundary species, held at its value.
- `antimony.steady_state(model)` finds the steady state, and
  `antimony.fluxes(model, y)` the reaction rates there.
- `antimony.simulator`, `step` and `set` advance a simulation in steps and
  change values between them.
- `E1: at (trigger): name = value` is an event: the assignments are done
  when the trigger becomes true, in `antimony.simulate`.
- `antimony.control(model)` gives the control coefficients.

## Exercises

1. In the first model, make B's removal faster, `k2 = 1.0`, and find how
   high B rises. (Simulate with `points = 201` and take the `max` of B's
   row.)
2. Extend the first model into a chain A -> B -> C, with C removed at rate
   `k3*C`, `k3 = 0.1`, and plot all three species.
3. A reversible reaction `J1: A -> B; kf*A - kr*B`, with `kf = 1` and
   `kr = 0.5`, starts from A = 10 and B = 0. Find its steady state. What is
   the ratio of B to A?
4. In the pathway, double the last step's maximum rate, to `Vm2 = 12`. What
   are the new steady-state concentrations?
5. In the first model, without B's removal, refill A to 10 whenever it
   falls below 1, and plot A over 20 time units. How often is it refilled?

## Answers

**Exercise 1.**

```axon
# fast_removal.sci: how high does B rise?
import antimony
model = antimony.load("""
  J1: A -> B; k1*A
  J2: B -> ; k2*B
  k1 = 0.5; k2 = 1.0
  A = 10; B = 0
""")
sol = antimony.simulate(model, 20, points = 201)
println("Highest B:", format(max(sol.y[2, :]), 3))
```

```output
Highest B: 2.500
```

**Exercise 2.** One more reaction, one more constant, one more starting
value:

```axon
# chain.sci: A to B to C
import antimony
import plot
model = antimony.load("""
  J1: A -> B; k1*A
  J2: B -> C; k2*B
  J3: C -> ; k3*C
  k1 = 0.5; k2 = 0.2; k3 = 0.1
  A = 10; B = 0; C = 0
""")
sol = antimony.simulate(model, 40)
for k in 1:length(sol.names)
  plot.line(sol.t, sol.y[k, :], label = sol.names[k])
end
plot.xlabel("time")
plot.ylabel("concentration")
plot.show()
```

**Exercise 3.** At steady state the forward and backward rates balance,
kf A = kr B, so B / A = kf / kr = 2. A + B stays at 10 throughout, because
the reaction only turns one into the other:

```axon
# reversible.sci: a reaction that runs both ways
import antimony
model = antimony.load("""
  J1: A -> B; kf*A - kr*B
  kf = 1; kr = 0.5
  A = 10; B = 0
""")
s = antimony.steady_state(model)
println("A =", format(s.y[1], 3), " B =", format(s.y[2], 3))
println("B / A =", format(s.y[2] / s.y[1], 3))
```

```output
A = 3.333  B = 6.667
B / A = 2.000
```

**Exercise 4.** S2 falls, because a faster last step needs less S2 to
carry the same flux; S1 does not change, because nothing about the steps
before S2 has changed:

```axon
# faster_step.sci: a faster last step
import antimony
pathway = antimony.load("""
  J0: $X0 -> S1; v0
  J1: S1 -> S2; Vm1*S1/(Km1 + S1)
  J2: S2 -> $X1; Vm2*S2/(Km2 + S2)
  v0 = 2; Vm1 = 10; Km1 = 1; Vm2 = 12; Km2 = 2
  X0 = 1; X1 = 0
""")
s = antimony.steady_state(pathway)
println("S1 =", format(s.y[1], 3), " S2 =", format(s.y[2], 3))
```

```output
S1 = 0.250  S2 = 0.400
```

**Exercise 5.** A falls from 10 to 1 in ln(10) / 0.5 = 4.6 time units, so it
is refilled four times in 20:

```axon
# refill.sci: A topped up whenever it runs low
import antimony
import plot
model = antimony.load("""
  J1: A -> B; k1*A
  k1 = 0.5
  A = 10; B = 0
  E1: at (A < 1): A = 10
""")
sol = antimony.simulate(model, 20)
plot.line(sol.t, sol.y[1, :])
plot.title("A, refilled")
plot.xlabel("time")
plot.ylabel("A")
plot.show()
println("Refilled", length(sol.t_events[1]), "times")
```

```output
Refilled 4 times
```

Next: [Lesson 11: Making programs fast](tutorial-11-speed.md)
