# Lesson 11: Making programs fast

[Tutorial](tutorial.md)

Most Axon programs are fast without any effort. When a function is first
called, Axon *compiles* it: it translates it into the computer's own
machine code, which runs hundreds of times faster than Axon working
through the program line by line, which is called *interpreting* it.
Loops at the top level of a program are compiled too. Occasionally
something in a function stops it from being compiled, and that part of the
program runs interpreted, and slowly. This lesson shows how to time code,
how to see what was compiled, and how to fix the common reasons when it was
not.

## Timing code

The `time` module measures how long code takes. `time.clock()` reads a
clock in seconds; the difference between two readings is the time in
between. `time.elapsed(f, ...)` calls a function and returns the seconds
it took, and `time.format` writes a time in sensible units:

```axon
# timing.sci: how long does a loop take?
import time

## The sum of 1/k for k from 1 to n.
function harmonic(n)
  total = 0.0
  for k in 1:n
    total = total + 1 / k
  end
  return total
end

println(harmonic(10000000))
seconds = time.elapsed(harmonic, 10000000)
println("Took", time.format(seconds))
```

On the computer this tutorial was written on, it printed

```text
16.6953113658573
Took 10.6 ms
```

Ten million additions in about a hundredth of a second. Your time will
differ, and it differs a little from run to run too.

## Compiled and interpreted

The **JIT** button in the toolbar, or **Run > Use JIT Compiler**, turns
compiling off and on. (JIT stands for *just in time*: functions are
compiled just before they are first used.) Run `timing.sci` with it off,
and the same program, giving the same answer, took

```text
16.6953113658573
Took 11.0 s
```

a thousand times longer. The answers are the same either way; only the time
differs. Turn the JIT back on before going on.

## The JIT report

After each run, the Output pane says what was compiled, in a grey note such
as `JIT compiled: harmonic`. When a function or loop in your program could
not be compiled, a note says so, with the reason, under the heading
*Interpreted (click a line to see where)*. The line in the editor is
underlined in red, and resting the mouse on it shows the reason too.

## The most common reason

Here is the same sum as a loop at the top level of a program, with one
small difference: the total starts as `0`, not `0.0`.

```axon
# slowloop.sci: a total that changes kind
n = 1000000
total = 0
for k in 1:n
  total = total + 1 / k
end
println(total)
```

```output
14.392726722865
```

The answer is right, but the loop runs interpreted, and the JIT report
explains why:

```text
loop at 4:1: total is int before the loop and real at 5:3; give it a real
value before the loop (0.0 rather than 0) so it stays a real
```

(`4:1` is line 4, column 1: where the loop starts.)

`0` is an integer, and `1 / k` is a real number, so `total` starts the
loop as an integer and becomes a real inside it. Compiled code needs each
variable to keep one kind of value, so this loop cannot be compiled. The
fix is what the report says: start with `0.0`.

```axon
# fastloop.sci: a total that stays real
n = 1000000
total = 0.0
for k in 1:n
  total = total + 1 / k
end
println(total)
```

```output
14.392726722865
```

The same answer, but the loop now took 2.35 ms instead of 1.07 s: more than
four hundred times faster, for one character. Whenever a variable will
hold real numbers, give it a real value from the start.

## Other things that keep code interpreted

The report always gives the reason. The common ones, after a variable that
changes kind, are:

- **A matrix of whole numbers.** `[2, 1; 4, 3]` is a matrix of integers,
  and compiled code works with matrices of reals. Write one entry as a
  real, `[2.0, 1; 4, 3]`, and the whole matrix is real.
- **Dictionaries, `try` and complex numbers in the loop.** They are not
  compiled. Read what you need from a dictionary before the loop, and keep
  results in a vector inside it.
- **`global`**. Pass the value into the function and return the new
  value instead.

The manual's section "When code stays slow" lists the rest.

## Working with whole vectors

Calculations on whole vectors, such as `sum` and `.^`, run inside Axon's
built-in functions, which are fast whether or not your code is compiled.
The harmonic sum can be written without a loop:

```axon
# vector_sum.sci: the harmonic sum without a loop
n = 10000000
println(sum(1 ./ (1:n)))
```

```output
16.6953113658573
```

This took about 0.1 s here: ten times longer than the compiled loop, which
needs no vector of ten million numbers, but a hundred times faster than the
loop interpreted. Both ways are good. Write whichever is clearer, and
measure if speed matters.

## Measure first

Most programs spend almost all their time in one place, usually the
innermost loop. Before changing a program to make it faster, time it, and
look at the JIT report: if everything was compiled, the program is
probably as fast as it will get. `time.bench(f, ...)` times a function
several times over and gives the best time, which is steadier than a single
measurement for quick functions:

```axon
# bench.sci: timing a quick function several times
import time

## The sum of 1/k for k from 1 to n.
function harmonic(n)
  total = 0.0
  for k in 1:n
    total = total + 1 / k
  end
  return total
end

b = time.bench(harmonic, 100000)
println("Best of", b.runs, "runs:", time.format(b.best))
```

`b.best` is the shortest time of `b.runs` runs, each of which calls the
function `b.loops` times.

## Summary

- Axon compiles functions, and loops at the top level, into machine code the
  first time they run; compiled code is hundreds of times faster.
- `time.clock`, `time.elapsed`, `time.bench` and `time.format` measure and
  show times.
- The **JIT** button turns compiling off and on, for comparison.
- After a run, the Output pane's notes say what was compiled, and why
  anything was not; the editor underlines the place.
- The most common reason is a variable that changes kind: start a total that
  will hold reals at `0.0`, not `0`.
- Calculations on whole vectors are fast even when not compiled.

## Exercises

1. Time `harmonic` for n = 1,000,000 and n = 10,000,000. How does the time
   grow with n?
2. The program below runs its loop interpreted. Run it, find out why from
   the JIT report, and fix it.
3. Write the sum of exercise 2 without a loop.

```axon
# squares.sci: the sum of a million squares
x = linspace(0, 1, 1000001)
total = 0
for k in 1:length(x)
  total = total + x[k]^2
end
println(format(total, 3))
```

```output
333333.833
```

## Answers

**Exercise 1.** The time grows in proportion to n: ten times as many terms
take about ten times as long. Your times will differ from anyone else's.

```axon
# grow.sci: time against n
import time

## The sum of 1/k for k from 1 to n.
function harmonic(n)
  total = 0.0
  for k in 1:n
    total = total + 1 / k
  end
  return total
end

for n in {1000000, 10000000}
  println(n, time.format(time.elapsed(harmonic, n)))
end
```

**Exercise 2.** `total` starts as the integer 0 and becomes real, because
`x[k]^2` is real. The report says so, and starting at `0.0` fixes it:

```axon
# squares_fast.sci: a total that stays real
x = linspace(0, 1, 1000001)
total = 0.0
for k in 1:length(x)
  total = total + x[k]^2
end
println(format(total, 3))
```

```output
333333.833
```

**Exercise 3.** `x.^2` squares every element, and `sum` adds them:

```axon
# squares_vector.sci: the same sum without a loop
x = linspace(0, 1, 1000001)
println(format(sum(x.^2), 3))
```

```output
333333.833
```

## Where next

This is the last lesson. You can now write programs that calculate, decide
and repeat, keep data in vectors, lists, records and files, draw it, and
solve equations, differential equations and reaction models. From here:

- The examples on the IDE's **Welcome** tab are complete programs on many
  subjects, to run, read and change.
- The *Axon User Manual* covers each topic of these lessons in more depth,
  and more besides: writing modules of your own, working with text, sparse
  matrices, drawing, and calling C libraries.
- **Help > Language Reference** describes every rule and every function
  exactly. Put the caret on any name and press <kbd>F1</kbd> for help on it.
