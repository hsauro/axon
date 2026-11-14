# Lesson 3: Writing your own functions

[Tutorial](tutorial.md)

Axon's own functions, such as `sqrt` and `log`, each do one job under a
name. In this lesson you write your own. A function gives a calculation a
name, so that you write it once and use it wherever you need it: a program
becomes shorter, easier to read, and easier to correct, because a mistake
is fixed in one place.

## Defining a function

Here is a function that converts a temperature from degrees Fahrenheit to
degrees Celsius, typed in the REPL:

```repl
> function celsius(f)
...   return (f - 32) * 5 / 9
... end
> celsius(98.6)
37.0
> celsius(212)
100.0
> c = celsius(50)
c = 10.0
```

The definition has four parts:

- `function` and the function's *name*, `celsius`;
- its *parameters* in brackets, here one, `f`: the values it is given;
- its *body*, the lines that do the work. `return` ends the function and
  gives back the value after it;
- `end`, which closes the definition.

Defining a function does not run it. It runs when it is *called*:
`celsius(98.6)` runs the body with `f` equal to 98.6, and the call is
replaced by the value returned. The value in the call, 98.6, is the
*argument*. A call can go anywhere a value can: in a calculation, in
`println`, or on the right of `=`.

## Functions in programs

In a program, define a function before the lines that call it. A comment
starting with `##` directly above the function describes what it does:

```axon
# temps.sci: a function that converts temperatures

## The temperature f, in degrees Fahrenheit, in degrees Celsius.
function celsius(f)
  return (f - 32) * 5 / 9
end

for f in 0:50:200
  println(f, "F is", format(celsius(f), 1), "C")
end
```

```output
0 F is -17.8 C
50 F is 10.0 C
100 F is 37.8 C
150 F is 65.6 C
200 F is 93.3 C
```

The `##` comment is the function's documentation. Put the caret on the
name `celsius` anywhere in the program and press <kbd>F1</kbd>: the Help
pane shows the function's parameters and that description, just as it does
for Axon's own functions. After running the program in the REPL
(<kbd>Shift+F9</kbd>), `help` shows it too:

```repl
> run "temps.sci"
0 F is -17.8 C
50 F is 10.0 C
100 F is 37.8 C
150 F is 65.6 C
200 F is 93.3 C
> help celsius
celsius(f)
  The temperature f, in degrees Fahrenheit, in degrees Celsius.
> celsius(100)
37.7777777777778
```

## Several parameters

A function can take several parameters, separated by commas, and one
function can call another:

```axon
# triangle.sci: the long side of a right-angled triangle

## x times itself.
function square(x)
  return x * x
end

## The hypotenuse of a right-angled triangle with sides a and b.
function hypotenuse(a, b)
  return sqrt(square(a) + square(b))
end

println(hypotenuse(3, 4))
println(hypotenuse(5, 12))
```

```output
5.0
13.0
```

The arguments are matched to the parameters in order: in `hypotenuse(5, 12)`,
`a` is 5 and `b` is 12.

## Returning or printing

A function can print, but a function that *returns* its result is more
useful. Compare:

```repl
> function show(x)
...   println("x is", x)
... end
> show(3)
x is 3
> y = show(3)
x is 3
y = nothing
```

`show` prints its argument, but has no `return`, so it gives back
`nothing`: a value that stands for "no value". A function that returns its
result can be used in further calculations, printed in any format, or put
in a table, as `celsius` was. Let functions compute and return, and print
the results where they are used.

## Variables inside a function

The parameters and the variables a function creates belong to the
function. They exist while it runs and are gone when it returns:

```repl
> function double_it(x)
...   result = 2 * x
...   return result
... end
> double_it(4)
8
> result
NameError: "result" is not defined
  at <repl>:1:1
```

A variable stored inside a function is the function's own, even when a
variable of the same name exists outside it, so a function cannot change
your program's variables by accident:

```repl
> k = 10
k = 10
> function set_k()
...   k = 99
...   return k
... end
> set_k()
99
> k
10
```

A function can read variables from outside it, but it is clearer to pass
everything it needs as arguments: then the function's first line says what
it depends on.

## Loops inside functions

A function's body can hold any lines: loops and decisions too. This one
adds up the whole numbers from 1 to `n`, with the pattern from Lesson 2:

```axon
# sumto.sci: the sum of 1 to n, as a function

## The sum of the whole numbers from 1 to n.
function sum_to(n)
  total = 0
  for k in 1:n
    total = total + k
  end
  return total
end

println(sum_to(10), sum_to(100))
```

```output
55 5050
```

`return` can also appear in the middle of a function: it ends the function
there and then, even inside a loop. A number is prime when no number
between 2 and itself divides it, so this function returns `false` as soon
as it finds a divisor, and `true` only when the loop has found none:

```axon
# prime.sci: which numbers are prime?

## True when n is a prime number.
function is_prime(n)
  if n < 2
    return false
  end
  for d in 2:n - 1
    if mod(n, d) == 0
      return false
    end
  end
  return true
end

for n in 1:20
  if is_prime(n)
    println(n)
  end
end
```

```output
2
3
5
7
11
13
17
19
```

A function that returns `true` or `false` can be used directly as a
condition, as in `if is_prime(n)`.

## Optional arguments

A parameter can have a *default value*, used when the call leaves it out:

```repl
> function power(x, n = 2)
...   return x^n
... end
> power(3)
9
> power(3, 3)
27
```

Parameters written after a semicolon are *keyword parameters*: a call
gives them by name, in any order, or leaves them at their defaults. They
suit constants that are usually the same but sometimes need changing. The
Michaelis-Menten law gives the rate of an enzyme reaction at substrate
concentration `s`, with two constants, `vmax` and `km`:

```axon
# mm.sci: the Michaelis-Menten rate law

## The rate of an enzyme reaction at substrate concentration s.
function rate(s; vmax = 10.0, km = 2.0)
  return vmax * s / (km + s)
end

println("s   rate")
for s in 0:2:10
  println(s, format(rate(s), 3))
end
println("With km = 0.5:", format(rate(1.0, km = 0.5), 3))
```

```output
s   rate
0 0.000
2 5.000
4 6.667
6 7.500
8 8.000
10 8.333
With km = 0.5: 6.667
```

`rate(s)` uses both defaults, and `rate(1.0, km = 0.5)` changes `km` only.
The name in the call makes it clear which constant is being changed.

## Returning two values

A function can return more than one value, separated by commas. To keep
them, put names for them in square brackets on the left of `=`. The roots
of a quadratic equation come as a pair:

```axon
# quad.sci: the roots of a quadratic equation

## The two roots of a x^2 + b x + c = 0, when they are real.
function roots(a, b, c)
  d = b^2 - 4 * a * c
  if d < 0
    error("ArgumentError", "the roots are not real")
  end
  r1 = (-b - sqrt(d)) / (2 * a)
  r2 = (-b + sqrt(d)) / (2 * a)
  return r1, r2
end

[x1, x2] = roots(1, -3, 2)
println("The roots are", x1, "and", x2)
```

```output
The roots are 1.0 and 2.0
```

`error` stops the program with an error message of your own, here when the
roots are not real numbers. A function should complain like this about
arguments it cannot handle, rather than return a wrong answer. Change the
call to `roots(1, 0, 1)`, which has no real roots, and the program stops:

```axon
# quad2.sci: a quadratic without real roots

## The two roots of a x^2 + b x + c = 0, when they are real.
function roots(a, b, c)
  d = b^2 - 4 * a * c
  if d < 0
    error("ArgumentError", "the roots are not real")
  end
  r1 = (-b - sqrt(d)) / (2 * a)
  r2 = (-b + sqrt(d)) / (2 * a)
  return r1, r2
end

[x1, x2] = roots(1, 0, 1)
println("The roots are", x1, "and", x2)
```

```output
ArgumentError: the roots are not real
  at quad2.sci:7:5 in roots
  at quad2.sci:14:12
```

The lines after the message show where the error happened, and how the
program got there: at line 7, inside `roots`, which was called from line
14. In the IDE, each of those lines is a link: click it to go to the line.

## Mistakes

Calling a function with the wrong number of arguments:

```repl
> function celsius(f)
...   return (f - 32) * 5 / 9
... end
> celsius(1, 2)
ArgumentError: celsius takes 1 positional argument(s), got 2
  at <repl>:1:1
```

Misspelling a keyword argument:

```repl
> function rate(s; vmax = 10.0, km = 2.0)
...   return vmax * s / (km + s)
... end
> rate(2.0, kk = 1.0)
ArgumentError: rate has no keyword parameter "kk"
  at <repl>:1:1
```

And forgetting `return`, so that the function gives back `nothing`. If a
call's value prints as `nothing`, or a calculation with it fails, look for
the missing `return`.

## Summary

- `function name(parameters)` ... `end` defines a function; `return value`
  ends it and gives back the value. A call, `name(arguments)`, runs it.
- A `##` comment above a function documents it, for <kbd>F1</kbd> and
  `help`.
- Define functions before the lines that call them. Functions can call
  other functions, and contain loops and decisions.
- A function without `return` gives back `nothing`. Return results rather
  than printing them.
- Variables made inside a function belong to it.
- `name = value` in the parameters gives a default; parameters after `;`
  are keywords, given by name in a call.
- `return a, b` returns two values, and `[x, y] = f(...)` keeps both.
- `error("Kind", "message")` stops with your own message.

## Exercises

1. Write `fahrenheit(c)`, which converts degrees Celsius to degrees
   Fahrenheit (multiply by 9, divide by 5, add 32). Check that
   `fahrenheit(celsius(77))` gives 77 again.
2. Write `sphere_volume(r)`, and print the volumes of spheres of radius 1
   to 5, with two decimals.
3. Write `bmi(mass, height)`, which returns the body mass index, and
   `category(b)`, which returns its category as text (the rules are in
   exercise 4 of Lesson 2). Print both for 70 kg and 1.75 m, and for 95 kg
   and 1.80 m.
4. Write `factorial_of(n)`, which multiplies together the whole numbers from
   1 to `n`. Axon has a function `factorial`: check that both give 120 for
   5.
5. The logistic equation describes a population that grows until it
   reaches the most its surroundings can support:
   N(t) = K / (1 + (K / N0 - 1) exp(-r t)). Write
   `logistic(t; n0 = 10.0, r = 0.5, k = 1000.0)` and print the population
   at t = 0, 5, 10, 15 and 20, with one decimal, for the default growth
   rate and for `r = 1.0`.
6. Use `is_prime` to count the prime numbers between 1 and 100.

## Answers

**Exercise 1.** Converting there and back gives 77 again:

```axon
# fahrenheit.sci: converting both ways

## The temperature c, in degrees Celsius, in degrees Fahrenheit.
function fahrenheit(c)
  return c * 9 / 5 + 32
end

## The temperature f, in degrees Fahrenheit, in degrees Celsius.
function celsius(f)
  return (f - 32) * 5 / 9
end

println(celsius(77), fahrenheit(celsius(77)))
```

```output
25.0 77.0
```

**Exercise 2.**

```axon
# spheres.sci: volumes of spheres

## The volume of a sphere of radius r.
function sphere_volume(r)
  return 4 / 3 * pi * r^3
end

for r in 1:5
  println(r, format(sphere_volume(r), 2))
end
```

```output
1 4.19
2 33.51
3 113.10
4 268.08
5 523.60
```

**Exercise 3.** Each `return` ends the function, so `category` needs no
`else`: the last line is reached only when no earlier condition held.

```axon
# bmi2.sci: body mass index with functions

## The body mass index of a person of the given mass (kg) and height (m).
function bmi(mass, height)
  return mass / height^2
end

## The category of a body mass index b.
function category(b)
  if b < 18.5
    return "underweight"
  elseif b < 25
    return "normal"
  elseif b < 30
    return "overweight"
  end
  return "obese"
end

b1 = bmi(70, 1.75)
println(format(b1, 1), category(b1))
b2 = bmi(95, 1.80)
println(format(b2, 1), category(b2))
```

```output
22.9 normal
29.3 overweight
```

**Exercise 4.** The product pattern: start at 1, and multiply.

```axon
# fact.sci: the factorial with a loop

## The product of the whole numbers from 1 to n.
function factorial_of(n)
  product = 1
  for k in 1:n
    product = product * k
  end
  return product
end

println(factorial_of(5), factorial(5))
```

```output
120 120
```

**Exercise 5.** With the faster growth rate, the population reaches the
limit of 1000 sooner.

```axon
# logistic.sci: logistic growth

## The size at time t of a population that grows logistically.
function logistic(t; n0 = 10.0, r = 0.5, k = 1000.0)
  return k / (1 + (k / n0 - 1) * exp(-r * t))
end

for t in 0:5:20
  println(t, format(logistic(t), 1), format(logistic(t, r = 1.0), 1))
end
```

```output
0 10.0 10.0
5 109.6 599.9
10 599.9 995.5
15 948.1 1000.0
20 995.5 1000.0
```

**Exercise 6.** A count is a total that goes up by one each time:

```axon
# countprimes.sci: how many primes up to 100?

## True when n is a prime number.
function is_prime(n)
  if n < 2
    return false
  end
  for d in 2:n - 1
    if mod(n, d) == 0
      return false
    end
  end
  return true
end

primes = 0
for n in 1:100
  if is_prime(n)
    primes = primes + 1
  end
end
println(primes)
```

```output
25
```

Next: [Lesson 4: Vectors and matrices](tutorial-04-vectors.md)
