# Lesson 8: Solving equations

[Tutorial](tutorial.md)

Many scientific questions come down to an equation to solve: the
concentration at which a reaction balances, the time at which a population
reaches a size, the slope of the line that best fits some measurements.
Lesson 4 solved linear equations with `\`. This lesson fits a line to data
with the same operator, then turns to equations that are not linear: first
by writing a simple method yourself, then with Axon's solver.

## Fitting a straight line

A spring stretches in proportion to the force on it. Six measurements of
force and extension should lie on a straight line, extension = a + b times
force, but measurements are never exact, so no line passes through all six
points. Each measurement gives one equation for the two unknowns `a` and
`b`: six equations, two unknowns. `\` finds the line that fits them best,
the one with the smallest sum of squared differences from the measurements,
which is what *least squares* means:

```axon
# spring.sci: fitting a straight line to measurements
import plot
force = [0.0; 1.0; 2.0; 3.0; 4.0; 5.0]              # N
extension = [0.02; 0.51; 0.98; 1.53; 2.01; 2.47]    # cm
A = [ones(6), force]
coef = A \ extension
println("Intercept:", format(coef[1], 3), "cm")
println("Slope:", format(coef[2], 3), "cm per N")
println("Spring constant:", format(1 / coef[2], 2), "N per cm")
f = linspace(0, 5, 2)
plot.scatter(force, extension, label = "measured")
plot.line(f, coef[1] + coef[2] * f, label = "fitted line")
plot.xlabel("force (N)")
plot.ylabel("extension (cm)")
plot.show()
```

```output
Intercept: 0.018 cm
Slope: 0.494 cm per N
Spring constant: 2.02 N per cm
```

Each row of `A` holds the numbers in front of `a` and `b` in one equation:
1, for `a`, and the force, for `b`. `ones(6)` is the column of ones, and
`[ones(6), force]` puts the two columns side by side. A straight line needs
only two points, so `f` has two.

## Equations that are not linear

Other equations cannot be solved by a matrix. Which x makes

```text
x^3 - 2 x - 5 = 0 ?
```

There is no simple formula for it, but a computer can find x to as many
digits as needed by trying values in a sensible order. Such an x is called
a *root* of the function f(x) = x^3 - 2x - 5: a value where f is zero.

## Halving the interval

At x = 2 the function is -1, and at x = 3 it is 16. It changes sign between
them, so a root lies in between. The *bisection* method tries the midpoint,
2.5, and keeps whichever half still has a change of sign; then it halves
that half, and so on. Each step halves the interval in which the root must
lie:

```axon
# bisect.sci: finding a root by halving an interval

## A root of f between a and b, where f(a) and f(b) have opposite signs.
function bisect(f, a, b)
  while b - a > 1e-10
    m = (a + b) / 2
    if f(a) * f(m) <= 0
      b = m
    else
      a = m
    end
  end
  return (a + b) / 2
end

## The function whose root we want.
function cubic(x)
  return x^3 - 2 * x - 5
end

root = bisect(cubic, 2.0, 3.0)
println("Root:", format(root, 8))
println("Check:", cubic(root))
```

```output
Root: 2.09455148
Check: 2.91990431833256e-10
```

`f(a) * f(m) <= 0` is true when `f(a)` and `f(m)` have opposite signs (or
one is zero): the root is then between `a` and `m`, so `m` becomes the new
`b`. Otherwise it is in the other half. After 34 halvings the interval is
narrower than 1e-10, and the check shows `cubic` is very nearly zero there.

`bisect` takes a *function* as its first argument: `bisect(cubic, 2.0, 3.0)`
passes the function `cubic` itself, without brackets, and inside `bisect`
the name `f` calls it. So the same `bisect` finds a root of any function.

A function can also be written where it is needed, without a name:
`function(x) return x^3 - 10 end` is a function of `x`, and
`bisect(function(x) return x^3 - 10 end, 2.0, 3.0)` finds the cube root of 10.

## The nonlin module

Bisection is safe but slow, and it only handles one unknown. The `nonlin`
module's `solve` uses Newton's method, which follows the slope of the
function to the root and usually needs only a few steps. It needs a
starting *guess* instead of an interval:

```repl
> import nonlin
> function cubic(x)
...   return x^3 - 2 * x - 5
... end
> r = nonlin.solve(cubic, 2.0)
r = {x: [2.09455], status: "success", fnorm: 8.88178419700125e-16, nfev: 9, niters: 4}
> r.x[1]
2.09455148154233
> cubic(r.x[1])
-8.88178419700125e-16
```

The result is a record. `x` holds the solution, as a vector even for one
unknown, so the root is `r.x[1]`; `status` says whether the solve
succeeded; and `niters` that it took 4 steps.

An equation can have several roots, and the guess decides which one is
found. x^2 - 2 = 0 has two:

```repl
> nonlin.solve(function(x) return x^2 - 2 end, 1.0).x[1]
1.41421356237469
> nonlin.solve(function(x) return x^2 - 2 end, -1.0).x[1]
-1.41421356237469
```

The solve stops once the function is within 1e-10 of zero, so the last
digits can differ from the exact root, the square root of 2,
1.41421356237310. Start from a guess near the root you want; a plot of the
function (Lesson 5) shows where its roots are.

## A chemical example

Acetic acid, at a concentration of 0.1 mol/L, partly splits into hydrogen
ions and acetate ions. The concentration x of hydrogen ions satisfies

```text
x^2 = Ka (c - x)
```

where c is 0.1 and the acid's constant Ka is 1.8e-5. The pH is minus the
logarithm to base 10 of x:

```axon
# acid.sci: the pH of a weak acid
import nonlin
ka = 1.8e-5      # the acid constant of acetic acid
c = 0.1          # mol/L
r = nonlin.solve(function(x) return x^2 - ka * (c - x) end, 1e-3)
println(r.status)
println("[H+] =", r.x[1], "mol/L")
println("pH =", format(-log10(r.x[1]), 2))
```

```output
success
[H+] = 0.00133267141097125 mol/L
pH = 2.88
```

The equation is rearranged so that one side is zero, as `solve` needs. The
function uses `ka` and `c` from the program around it, so changing them and
running again solves the equation for another acid.

## Several equations at once

`nonlin.solve` also solves several equations in several unknowns. The
function then takes a vector of the unknowns and returns a vector with one
value per equation, each zero at the solution. Where does the circle
x^2 + y^2 = 4 cross the parabola y = x^2?

```axon
# crossing.sci: where a circle crosses a parabola
import nonlin

## Both equations, written so that each is zero at a crossing.
function crossing(v)
  x = v[1]
  y = v[2]
  return [x^2 + y^2 - 4; y - x^2]
end

s = nonlin.solve(crossing, [1.0; 1.0])
println(s.status)
println("x =", format(s.x[1], 4), " y =", format(s.x[2], 4))
```

```output
success
x = 1.2496  y = 1.5616
```

The guess `[1.0; 1.0]` is a vector too, one value per unknown.

## When there is no solution

x^2 + 1 is never zero, so `solve` cannot succeed. After 200 steps it gives
up and stops the program with an error:
`SolverError: nonlin.solve: no solution after 200 iterations`. When this
happens with an equation that should have a solution, try another guess,
and check the function by plotting it.

## Summary

- `A \ b` with more equations than unknowns gives the least-squares fit;
  `A = [ones(n), x]` fits a straight line.
- A root of f is a value where f is zero. Bisection finds one by halving an
  interval in which f changes sign.
- A function can be passed to another function by name, without brackets,
  or written in place: `function(x) return ... end`.
- `nonlin.solve(f, guess)` solves f(x) = 0 by Newton's method; the solution
  is `r.x`, with `r.status` saying whether it succeeded.
- For several equations, `f` takes and returns a vector, and the guess is a
  vector.
- The guess decides which root is found.

## Exercises

1. Use `bisect` to find the cube root of 10, a root of x^3 - 10 between 2
   and 3.
2. Solve cos x = x with `nonlin.solve`, starting from 0.5. (Rearrange it so
   that one side is zero.)
3. Formic acid has Ka = 1.8e-4. What is the pH of a 0.05 mol/L solution?
4. The circle and the parabola cross twice. Find the other crossing.
5. A ball is thrown upwards. Its height h at times t = 0, 0.5, 1, 1.5 and
   2 s was 10.0, 12.3, 12.1, 9.5 and 4.4 m. Fit h = a + b t + c t^2 by least
   squares: the matrix needs a third column, of t squared. c should be
   about minus half of 9.81, the acceleration of gravity.

## Answers

**Exercise 1.** The function is written in place:

```axon
# cuberoot.sci: the cube root of 10 by bisection

## A root of f between a and b, where f(a) and f(b) have opposite signs.
function bisect(f, a, b)
  while b - a > 1e-10
    m = (a + b) / 2
    if f(a) * f(m) <= 0
      b = m
    else
      a = m
    end
  end
  return (a + b) / 2
end

println(format(bisect(function(x) return x^3 - 10 end, 2.0, 3.0), 8))
```

```output
2.15443469
```

**Exercise 2.** cos x = x is the same as cos x - x = 0:

```axon
# cosx.sci: where cos x equals x
import nonlin
r = nonlin.solve(function(x) return cos(x) - x end, 0.5)
println(format(r.x[1], 6))
```

```output
0.739085
```

**Exercise 3.** Only `ka` and `c` change:

```axon
# formic.sci: the pH of formic acid
import nonlin
ka = 1.8e-4
c = 0.05
r = nonlin.solve(function(x) return x^2 - ka * (c - x) end, 1e-3)
println("pH =", format(-log10(r.x[1]), 2))
```

```output
pH = 2.54
```

**Exercise 4.** The curves are symmetric about the y axis, so start from a
guess with negative x:

```axon
# crossing2.sci: the other crossing
import nonlin

## Both equations, written so that each is zero at a crossing.
function crossing(v)
  x = v[1]
  y = v[2]
  return [x^2 + y^2 - 4; y - x^2]
end

s = nonlin.solve(crossing, [-1.0; 1.0])
println("x =", format(s.x[1], 4), " y =", format(s.x[2], 4))
```

```output
x = -1.2496  y = 1.5616
```

**Exercise 5.** Three columns, for a, b and c:

```axon
# ball.sci: fitting a parabola
t = [0.0; 0.5; 1.0; 1.5; 2.0]
h = [10.0; 12.3; 12.1; 9.5; 4.4]
B = [ones(5), t, t.^2]
coef = B \ h
println("a =", format(coef[1], 2), " b =", format(coef[2], 2), " c =", format(coef[3], 2))
println("Gravity:", format(-2 * coef[3], 2), "m/s^2")
```

```output
a = 10.00  b = 7.03  c = -4.91
Gravity: 9.83 m/s^2
```

Next: [Lesson 9: Differential equations](tutorial-09-differential-equations.md)
