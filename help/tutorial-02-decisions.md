# Lesson 2: Decisions and repetition

[Tutorial](tutorial.md)

The programs in Lesson 1 ran each line once, from top to bottom. Most
calculations need more: they must choose between steps (if the solution is
acidic, do one thing, otherwise another) and repeat steps (once for every
measurement, or until a value is small enough). This lesson shows how: true
and false values, `if` for decisions, and `for` and `while` for repetition.
It also shows how the editor and the REPL work together.

## Working in the editor

From now on most examples are programs of several lines. Type them in the
editor (**File > New**, <kbd>Ctrl+N</kbd>), save them under the name in
their first line, and run them with <kbd>F9</kbd>. A program can be changed
and run again as often as you like, which is much easier than retyping
lines in the REPL.

The REPL is still useful for trying a single line, and for looking at a
program's variables after it has run: this lesson shows how.

## True or false

A *comparison* asks a question whose answer is `true` or `false`:

```repl
> 3 < 5
true
> 3 > 5
false
> 2 + 2 == 4
true
> 2 + 2 != 4
false
> 7 >= 7
true
```

The comparisons are `<` (less than), `<=` (less than or equal to), `>`,
`>=`, `==` (equal to) and `!=` (not equal to). Note the two equals signs in
`==`: a single `=` stores a value, as in Lesson 1, while `==` asks whether
two values are equal. `true` and `false` are values of their own kind,
`bool`, and work for text as well as numbers:

```repl
> typeof(true)
"bool"
> "cat" == "dog"
false
```

`and`, `or` and `not` combine questions. `x > 10 and x < 20` is true when
both parts are true, `or` when at least one is, and `not` turns true into
false and false into true:

```repl
> x = 15
x = 15
> x > 10 and x < 20
true
> x < 10 or x > 20
false
> not (x > 10)
false
```

## Making a decision: if

`if` runs some lines only when a condition is true. This program says
whether a solution is acidic, neutral or basic:

```axon
# ph.sci: is a solution acidic, neutral or basic?
pH = 8.2
if pH < 7
  println("acidic")
elseif pH == 7
  println("neutral")
else
  println("basic")
end
```

```output
basic
```

Axon tries the conditions in order. The lines under the first one that is
true run, and the rest are skipped; if none is true, the lines under `else`
run. `elseif` and `else` are optional, and there can be as many `elseif`
parts as you need. `end` closes the whole `if`.

The lines inside are indented by two spaces. Axon does not need this, but it
shows at a glance which lines belong to which part. Change `pH` to 7, and
then to 3, and run the program again each time.

## Repeating: for

`for` runs the same lines once for each number in a range. `1:6` is the
range of whole numbers from 1 to 6. This program follows a population of
bacteria that doubles every 20 minutes:

```axon
# doubling.sci: a population of bacteria that doubles every 20 minutes
population = 1
for step in 1:6
  population = 2 * population
  minutes = 20 * step
  println(minutes, "minutes:", population, "cells")
end
```

```output
20 minutes: 2 cells
40 minutes: 4 cells
60 minutes: 8 cells
80 minutes: 16 cells
100 minutes: 32 cells
120 minutes: 64 cells
```

The lines between `for` and `end` are the *body* of the loop. They run six
times: the first time with `step` equal to 1, then 2, and so on up to 6.
Each time round, `population` doubles. Change `1:6` to `1:9` to follow the
population for three hours.

A range can also count in other steps: `0:0.5:2` goes from 0 to 2 in steps
of 0.5, and `5:-1:1` counts down from 5 to 1. In the REPL, a loop of several
lines shows a `...` prompt until its `end` is typed:

```repl
> for t in 0:0.5:2
...   println(t)
... end
0.0
0.5
1.0
1.5
2.0
```

The loop's counter, `t` here, exists only inside the loop.

### A program's variables in the REPL

After a program has run with <kbd>F9</kbd>, its variables are gone. Press
<kbd>Shift+F9</kbd> instead (**Run > Run in REPL**), and the program runs in
the REPL, where its variables stay. You can then ask about them:

```repl
> run "doubling.sci"
20 minutes: 2 cells
40 minutes: 4 cells
60 minutes: 8 cells
80 minutes: 16 cells
100 minutes: 32 cells
120 minutes: 64 cells
> population
64
> minutes
120
```

<kbd>Shift+F9</kbd> types the `run` line for you, with the file's full
name. This is a good way to work: write the program in the editor, run it
in the REPL, and look at what it computed. <kbd>Ctrl+Enter</kbd> in the
editor sends just the current line (or the selected lines) to the REPL, to
try one part of a program.

## Adding up in a loop

A common use of a loop is to add up many values. Start a total at 0, and
add each value to it inside the loop:

```axon
# total.sci: the sum of the whole numbers from 1 to 100
total = 0
for k in 1:100
  total = total + k
end
println("The total is", total)
```

```output
The total is 5050
```

Each time round the loop, `total = total + k` adds the next number to the
total so far: 0 + 1, then 1 + 2, then 3 + 3, and so on. The same pattern
counts things, finds averages and builds up any running result.

## Decisions inside loops

The body of a loop can contain an `if`, which decides afresh each time
round. `mod(k, 2)` is the remainder after dividing `k` by 2, which is 0
exactly when `k` is even:

```axon
# evenodd.sci: which numbers are even?
for k in 1:6
  if mod(k, 2) == 0
    println(k, "is even")
  else
    println(k, "is odd")
  end
end
```

```output
1 is odd
2 is even
3 is odd
4 is even
5 is odd
6 is even
```

Each `end` closes the nearest open `if` or `for`; the indentation makes the
pairs easy to see.

## Repeating until: while

A `for` loop runs a known number of times. Sometimes you do not know in
advance how many repetitions are needed, only when to stop. `while` repeats
its body as long as its condition is true. A drug's concentration in the
blood halves every 6 hours; how long until it falls below 1 mg/L?

```axon
# halflife.sci: how long until a drug falls below 1 mg/L?
concentration = 100.0     # mg/L
hours = 0
while concentration >= 1.0
  concentration = concentration / 2
  hours = hours + 6
end
println("After", hours, "hours:", concentration, "mg/L")
```

```output
After 42 hours: 0.78125 mg/L
```

Before each repetition Axon checks the condition. Once the concentration is
below 1, the condition is false and the loop ends. A comment can also follow
code on the same line, as `# mg/L` does here.

`break` leaves a loop at once, wherever it is in the body. This program
looks for the first square number larger than 1000. `while true` repeats
for ever, until `break` ends it:

```axon
# search.sci: the first square number above 1000
n = 1
while true
  if n^2 > 1000
    break
  end
  n = n + 1
end
println(n, "squared is", n^2)
```

```output
32 squared is 1024
```

If the condition of a `while` never becomes false, the loop never ends and
the program seems to hang. Press **Stop** (<kbd>Ctrl+F2</kbd>) to end it,
and check that the body changes what the condition tests.

## Mistakes

Every `if`, `for` and `while` needs its `end`. Without it, Axon reaches the
end of the file still waiting for one:

```axon
# noend.sci
total = 0
for k in 1:10
  total = total + k
println(total)
```

```output
SyntaxError: expected "end" to close "for" from line 3, found end of file
  at noend.sci:6:1
```

The message names the line where the unclosed `for` starts, which is where
to look. Two more mistakes are common. Writing `=` where `==` is meant:

```repl
> if x = 3
SyntaxError: expected an expression, found "="
  at <repl>:1:6
```

And a condition that is not true or false. A number is not a condition:
write the comparison you mean, such as `x != 0`.

```repl
> if 1
...   println("one")
... end
TypeError: the condition of "if" must be a bool, got int
  at <repl>:1:1
```

## Summary

- Comparisons (`<`, `<=`, `>`, `>=`, `==`, `!=`) give `true` or `false`,
  and `and`, `or` and `not` combine them. `==` compares; `=` stores.
- `if` ... `elseif` ... `else` ... `end` runs the lines under the first
  condition that is true.
- `for k in 1:n` ... `end` repeats its body once for each number in the
  range. Ranges can step: `0:0.5:2`, `5:-1:1`.
- To add up values, start a total at 0 and add to it inside a loop.
- `while condition` ... `end` repeats as long as the condition is true;
  `break` leaves a loop early. **Stop** ends a loop that never finishes.
- <kbd>Shift+F9</kbd> runs a program in the REPL, where you can look at its
  variables afterwards.

## Exercises

1. Write a program that counts down from 10 to 1, printing each number on
   its own line, and then prints `Lift off!`.
2. Add up the squares of the whole numbers from 1 to 10 (1 + 4 + 9 + ...).
3. A bacterium divides every 20 minutes. Starting from one cell, how many
   cells are there after 6 hours? Use a loop.
4. The body mass index is the mass in kilograms divided by the square of
   the height in metres. Below 18.5 is underweight, below 25 normal, below
   30 overweight, and 30 or more obese. Write a program that works out the
   index of a person of 70 kg and 1.75 m, and prints it, with one decimal,
   and its category. (A variable can hold text, such as
   `category = "normal"`.)
5. A herd of 50 deer grows by 8% a year: each year the number is multiplied
   by 1.08. After how many years has the herd at least doubled?
6. Print the multiples of 7 between 1 and 50. There are two ways: test each
   number with `mod`, or use a range that steps by 7. Try both.

## Answers

**Exercise 1.** The range `10:-1:1` counts down.

```axon
# countdown.sci: count down, then lift off
for k in 10:-1:1
  println(k)
end
println("Lift off!")
```

```output
10
9
8
7
6
5
4
3
2
1
Lift off!
```

**Exercise 2.** The total pattern, adding `k^2` instead of `k`:

```axon
# squares.sci: the sum of the first ten squares
total = 0
for k in 1:10
  total = total + k^2
end
println(total)
```

```output
385
```

**Exercise 3.** Six hours is 360 minutes, so the cells divide 360 / 20 = 18
times, and the number doubles each time:

```axon
# cells.sci: cells after 18 divisions
cells = 1
for k in 1:18
  cells = 2 * cells
end
println(cells)
```

```output
262144
```

The same number is `2^18`; the loop shows how it builds up.

**Exercise 4.** The conditions are tried in order, so the second one only
needs to say `bmi < 25`: the first has already dealt with anything below
18.5.

```axon
# bmi.sci: body mass index and its category
mass = 70        # kg
height = 1.75    # m
bmi = mass / height^2
if bmi < 18.5
  category = "underweight"
elseif bmi < 25
  category = "normal"
elseif bmi < 30
  category = "overweight"
else
  category = "obese"
end
println("BMI", format(bmi, 1), "is", category)
```

```output
BMI 22.9 is normal
```

**Exercise 5.** A `while` loop, because the number of years is what we want
to find:

```axon
# deer.sci: years until the herd doubles
herd = 50.0
years = 0
while herd < 100
  herd = herd * 1.08
  years = years + 1
end
println("Doubled after", years, "years")
```

```output
Doubled after 10 years
```

**Exercise 6.** Testing every number:

```axon
# sevens.sci: multiples of 7 up to 50
for k in 1:50
  if mod(k, 7) == 0
    println(k)
  end
end
```

```output
7
14
21
28
35
42
49
```

or stepping by 7, which prints the same:

```axon
# sevens2.sci: multiples of 7 up to 50, by steps of 7
for k in 7:7:50
  println(k)
end
```

```output
7
14
21
28
35
42
49
```

Next: [Lesson 3: Writing your own functions](tutorial-03-functions.md)
