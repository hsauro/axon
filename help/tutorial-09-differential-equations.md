# Lesson 9: Differential equations

[Tutorial](tutorial.md)

Much of science describes how things change: a population grows at a rate
that depends on its size, a drug is removed from the blood at a rate
proportional to its concentration, predators and prey rise and fall
together. Such a description is a *differential equation*: it gives the
rate of change of a quantity, dy/dt, in terms of the quantity itself. This
lesson shows how a computer follows such an equation through time, first
by hand and then with the `ode` module, which does it accurately and
quickly.

## Stepping by hand

A culture of 100 bacteria grows at a rate of 0.5 per hour: in a short time
dt, the number y grows by about 0.5 y dt. Starting from the number now, a
loop can take small steps forward in time, adding the growth over each
step. This is *Euler's method*:

```axon
# euler.sci: growth followed in small steps
r = 0.5          # growth rate, per hour
y = 100.0        # cells at the start
dt = 0.1         # hours per step
for step in 1:40
  y = y + dt * r * y
end
println("Euler:", format(y, 1))
println("Exact:", format(100 * exp(r * 4), 1))
```

```output
Euler: 704.0
Exact: 738.9
```

Forty steps of 0.1 hours take the culture to 4 hours. The exact answer for
this simple equation is 100 e^(0.5 t), and Euler's method falls short of it,
because it uses the growth rate at the start of each step for the whole
step, while the real rate keeps rising during it. Smaller steps make the
error smaller, but more of them are needed. Exercise 1 tries it.

## The ode module

`ode.solve` does the stepping for you, with a far more accurate method that
also chooses the size of each step so as to meet a given accuracy. It needs
three things: a function `f(t, y)` that gives the rate of change at time `t`
when the quantity is `y`; the starting value; and the time span. A drug is
removed from the blood at a rate of 0.2 per hour, so
dC/dt = -0.2 C:

```axon
# elimination.sci: a drug removed from the blood
import ode
import plot
k = 0.2          # elimination rate, per hour

## The rate of change of the concentration c at time t.
function elimination(t, c)
  return -k * c
end

sol = ode.solve(elimination, 100.0, [0, 24], t_eval = linspace(0, 24, 101))
for t in 0:6:24
  println(t, format(sol.at(t)[1], 2), format(100 * exp(-k * t), 2))
end
plot.line(sol.t, sol.y[1, :])
plot.title("Drug concentration")
plot.xlabel("time (hours)")
plot.ylabel("concentration (mg/L)")
plot.show()
```

```output
0 100.00 100.00
6 30.12 30.12
12 9.07 9.07
18 2.73 2.73
24 0.82 0.82
```

The table's second column is the solver's answer and the third the exact
formula: they agree. The result `sol` is a record:

- `sol.t` holds the times at which the solution was reported; `t_eval`
  asked for 101 evenly spaced times, which make a smooth plot.
- `sol.y` holds the solution, one row per quantity and one column per time,
  so `sol.y[1, :]` is the concentration at every reported time.
- `sol.at(t)` gives the solution at any time in the span, as a vector.

The function gets `c` as a vector, even for one equation, and `-k * c`
returns a vector too. Like a function you plot, it should calculate with the
whole vector.

## Several equations: predators and prey

Rabbits breed, and foxes eat rabbits. With more rabbits the foxes thrive,
until they eat so many that the rabbits decline, and then the foxes starve.
The Lotka-Volterra equations describe this with two rates of change, one
for each species:

```text
rabbits' = a rabbits - b rabbits foxes
foxes'   = -c foxes + d rabbits foxes
```

With two quantities, `y` is a vector of both, and the function returns a
vector of both rates:

```axon
# lotka.sci: rabbits and foxes
import ode
import plot
a = 1.0      # the rabbits' birth rate
b = 0.1      # how fast foxes eat rabbits
c = 1.5      # the foxes' death rate
d = 0.075    # how fast foxes grow on the rabbits they eat

## The rates of change of the rabbits, y[1], and the foxes, y[2].
function rates(t, y)
  rabbits = y[1]
  foxes = y[2]
  return [a * rabbits - b * rabbits * foxes;
          -c * foxes + d * rabbits * foxes]
end

sol = ode.solve(rates, [10.0; 5.0], [0, 15], t_eval = linspace(0, 15, 300))
plot.line(sol.t, sol.y[1, :], label = "rabbits")
plot.line(sol.t, sol.y[2, :], label = "foxes")
plot.title("Predators and prey")
plot.xlabel("time")
plot.ylabel("population")
plot.show()
println("Most rabbits:", format(max(sol.y[1, :]), 1))
println("Most foxes:", format(max(sol.y[2, :]), 1))
```

```output
Most rabbits: 40.6
Most foxes: 23.3
```

The populations rise and fall in cycles, the foxes' peaks following the
rabbits'. Naming `y[1]` and `y[2]` inside the function, as `rabbits` and
`foxes`, makes the equations read as they are written above. Change `b` or
the starting numbers and run again to see how the cycles change.

## Stopping when something happens

Sometimes the question is not the value at a given time but the time at
which something happens: when does the drug fall below 1 mg/L? An *event
function* answers it. The solver watches it, and notes the time at which it
crosses zero; with `terminal = true`, the solve stops there:

```axon
# threshold.sci: when does the drug fall below 1 mg/L?
import ode
k = 0.2

## The rate of change of the concentration c at time t.
function elimination(t, c)
  return -k * c
end

## Zero when the concentration is 1 mg/L.
function below(t, c)
  return c[1] - 1.0
end

sol = ode.solve(elimination, 100.0, [0, 48], events = below, terminal = true)
println(sol.status)
println("Below 1 mg/L after", format(sol.t_events[1][1], 2), "hours")
```

```output
event
Below 1 mg/L after 23.03 hours
```

`sol.status` is `"event"` because an event stopped the solve.
`sol.t_events` is a list with one entry per event function, each a vector
of the times at which it occurred, so the first time of the first event is
`sol.t_events[1][1]`. (The exact answer is ln(100) / 0.2 = 23.03 hours.)

## Fast and slow together

Some systems, common in chemistry, combine very fast and very slow
changes: a reaction that is over in a microsecond inside one that takes
hours. The default method must then take tiny steps for the whole time,
and can take very long. Such equations are called *stiff*. For them, give
`method = "bdf"`, a method designed for stiff equations:
`ode.solve(f, y0, [0, 100], method = "bdf")`.

## Mistakes

The rate function must return one rate for each quantity: for two
quantities, a vector of two. If it returns the wrong number, the solve
stops with a `DimensionError`.

Inside the function, `y` is always a vector. For one equation, write
`c[1]` where a single number is needed, as `below` does, or calculate with
the whole vector, as `elimination` does.

## Summary

- A differential equation gives a rate of change, dy/dt = f(t, y).
  Euler's method follows it in small steps: y = y + dt f(t, y).
- `ode.solve(f, y0, [t0, t1])` solves it accurately; `t_eval` chooses the
  reported times.
- The result has `sol.t`, `sol.y` (one row per quantity) and `sol.at(t)`.
- For several quantities, `y` and the rates are vectors.
- `events = g` with `terminal = true` stops the solve where `g` crosses
  zero; the time is in `sol.t_events`.
- `method = "bdf"` is for stiff equations.

## Exercises

1. Run `euler.sci` with steps of 0.01 hours (400 of them). How close does
   it get to the exact answer?
2. Solve the logistic equation dN/dt = 0.5 N (1 - N / 1000) from N = 10,
   and compare its value at t = 10 with the formula of Lesson 3, which gave
   599.9.
3. In the SIR model of an epidemic, a population of 1000 is divided into
   the susceptible S, the infected I and the recovered R. Infections happen
   at a rate 0.3 S I / 1000, and recoveries at 0.1 I. Starting from one
   infected person, plot the three groups over 160 days, and find the day
   on which the most people are infected.
4. A cup of coffee at 90 degrees cools in a room at 20 degrees following
   dT/dt = -0.1 (T - 20), with t in minutes. When is it cool enough to
   drink, at 60 degrees?
5. Plot the foxes against the rabbits, one point for each time, instead of
   both against time. What shape do the cycles make?

## Answers

**Exercise 1.** Ten times as many steps, ten times smaller, bring Euler's
method much closer to 738.9:

```axon
# euler2.sci: smaller steps
r = 0.5
y = 100.0
dt = 0.01
for step in 1:400
  y = y + dt * r * y
end
println("Euler:", format(y, 1))
```

```output
Euler: 735.2
```

**Exercise 2.** `n` is a vector, so the rate uses `.*`:

```axon
# logistic_ode.sci: the logistic equation solved
import ode

## The rate of change of a logistically growing population n.
function logistic(t, n)
  return 0.5 * n .* (1 - n / 1000)
end

sol = ode.solve(logistic, 10.0, [0, 20])
println(format(sol.at(10.0)[1], 1))
```

```output
599.9
```

**Exercise 3.** Three quantities, three rates. The peak is found as in
Lesson 4, exercise 6:

```axon
# sir.sci: an epidemic
import ode
import plot
beta = 0.3       # infection rate
gamma = 0.1      # recovery rate
people = 1000

## The rates of change of the susceptible, infected and recovered.
function sir(t, y)
  infection = beta * y[1] * y[2] / people
  recovery = gamma * y[2]
  return [-infection; infection - recovery; recovery]
end

sol = ode.solve(sir, [999.0; 1.0; 0.0], [0, 160], t_eval = linspace(0, 160, 161))
plot.line(sol.t, sol.y[1, :], label = "susceptible")
plot.line(sol.t, sol.y[2, :], label = "infected")
plot.line(sol.t, sol.y[3, :], label = "recovered")
plot.xlabel("day")
plot.ylabel("people")
plot.show()

infected = sol.y[2, :]
peak = 1
for k in 2:length(infected)
  if infected[k] > infected[peak]
    peak = k
  end
end
println("Most infected:", format(infected[peak], 0), "on day", sol.t[peak])
```

```output
Most infected: 301 on day 38.0
```

**Exercise 4.** An event at 60 degrees:

```axon
# coffee.sci: when can I drink it?
import ode

## The rate of change of the temperature.
function cooling(t, temp)
  return -0.1 * (temp - 20)
end

## Zero at 60 degrees.
function drinkable(t, temp)
  return temp[1] - 60
end

sol = ode.solve(cooling, 90.0, [0, 60], events = drinkable, terminal = true)
println("After", format(sol.t_events[1][1], 2), "minutes")
```

```output
After 5.60 minutes
```

**Exercise 5.** The cycles make a closed loop: the populations come back
to where they started, and go round again.

```axon
# phase.sci: foxes against rabbits
import ode
import plot
a = 1.0
b = 0.1
c = 1.5
d = 0.075

## The rates of change of the rabbits, y[1], and the foxes, y[2].
function rates(t, y)
  rabbits = y[1]
  foxes = y[2]
  return [a * rabbits - b * rabbits * foxes;
          -c * foxes + d * rabbits * foxes]
end

sol = ode.solve(rates, [10.0; 5.0], [0, 15], t_eval = linspace(0, 15, 300))
plot.line(sol.y[1, :], sol.y[2, :])
plot.title("Foxes against rabbits")
plot.xlabel("rabbits")
plot.ylabel("foxes")
plot.show()
```
