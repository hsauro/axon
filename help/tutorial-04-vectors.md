# Lesson 4: Vectors and matrices

[Tutorial](tutorial.md)

Science rarely deals with one number at a time: an experiment gives a
series of measurements, a simulation a value at each time point, a survey a
table of results. A *vector* holds a list of numbers under one name, and a
*matrix* a table of them. This lesson shows how to make them, pick out
their elements, calculate with them as a whole, and solve equations with
them.

## Vectors

A vector is written in square brackets, with its numbers separated by
semicolons. Here are the heights of four people, in metres:

```repl
> heights = [1.62; 1.75; 1.80; 1.68]
heights = 4-vector{real}
  1.62
  1.75
   1.8
  1.68
```

`4-vector{real}` says that `heights` holds four real numbers; they are shown
one below the other. Functions such as `length`, `sum`, `mean`, `max`,
`min` and `sort` work on a whole vector:

```repl
> length(heights)
4
> sum(heights)
6.85
> mean(heights)
1.7125
> max(heights)
1.8
> sort(heights)
4-vector{real}
  1.62
  1.68
  1.75
   1.8
```

## Picking out elements

Each number in a vector has a position, counted from 1. `heights[1]` is the
first element, and `end` stands for the last position. A range picks out
several elements at once:

```repl
> heights[1]
1.62
> heights[end]
1.68
> heights[2:3]
2-vector{real}
  1.75
   1.8
```

The square brackets after a name pick out elements, and an element can be
changed by storing a new value in it:

```repl
> heights[2] = 1.77
> heights
4-vector{real}
  1.62
  1.77
   1.8
  1.68
```

Asking for a position the vector does not have is an error:

```repl
> heights[5]
IndexError: index 5 is out of bounds for a dimension of length 4
  at <repl>:1:9
```

## Calculating with whole vectors

Arithmetic between a vector and a single number applies to every element.
Converting the heights to centimetres needs no loop:

```repl
> heights * 100
4-vector{real}
  162.0
  177.0
  180.0
  168.0
```

Functions such as `sqrt`, `exp`, `log` and `sin` also work element by
element:

```repl
> sqrt([4.0; 9.0; 16.0])
3-vector{real}
  2.0
  3.0
  4.0
```

Two vectors of the same length can be added and subtracted with `+` and
`-`, element by element. To multiply, divide or raise them to a power
element by element, put a dot before the operator: `.*`, `./` and `.^`.
This program works out the body mass index of all four people at once:

```axon
# bmi_all.sci: the body mass index of four people
masses = [55.0; 72.0; 80.0; 61.0]     # kg
heights = [1.62; 1.75; 1.80; 1.68]    # m
bmi = masses ./ heights.^2
for k in 1:length(bmi)
  println("Person", k, format(bmi[k], 1))
end
println("Mean:", format(mean(bmi), 1))
```

```output
Person 1 21.0
Person 2 23.5
Person 3 24.7
Person 4 21.6
Mean: 22.7
```

`heights.^2` squares each height, and `masses ./ heights.^2` divides each
mass by its own squared height. The loop uses `length(bmi)`, so it works
for any number of people.

The dots matter. Without them, `*`, `/` and `^` are the operations of
matrix algebra, which mean something quite different for vectors.
`heights * heights` is an error, which at least tells you; but
`masses / heights.^2`, without the dot, quietly gives a 4 by 4 table of
numbers that are not body mass indices. When you mean element by element,
use the dot.

## Making vectors

Typing every number is fine for a few measurements. Other vectors are
easier to make with a function:

```repl
> linspace(0, 1, 5)
5-vector{real}
   0.0
  0.25
   0.5
  0.75
   1.0
> zeros(3)
3-vector{real}
  0.0
  0.0
  0.0
> (1:5).^2
5-vector{int}
   1
   4
   9
  16
  25
```

`linspace(a, b, n)` gives `n` evenly spaced numbers from `a` to `b`, and
`zeros(n)` and `ones(n)` give `n` zeros or ones. A range becomes a vector
when you calculate with it, as `(1:5).^2` does.

`linspace` is the natural way to make the times at which to work something
out. A drug whose concentration halves every 6 hours has, after `t` hours,
100 times 0.5 to the power `t / 6` per cent of its starting concentration:

```axon
# decay.sci: a drug's concentration over two days
t = linspace(0, 48, 9)              # hours
c = 100 * 0.5 .^ (t / 6)            # mg/L
for k in 1:length(t)
  println(t[k], c[k])
end
```

```output
0.0 100.0
6.0 50.0
12.0 25.0
18.0 12.5
24.0 6.25
30.0 3.125
36.0 1.5625
42.0 0.78125
48.0 0.390625
```

One line computes all nine concentrations, where Lesson 2 needed a loop.

A vector can also be filled in a loop. Start with `zeros`, then store into
each position. Here each element is worked out from the one before it:

```axon
# cells.sci: a population that doubles at each step
cells = zeros(7)
cells[1] = 1
for k in 2:7
  cells[k] = 2 * cells[k - 1]
end
println(cells)
```

```output
7-vector{real}
   1.0
   2.0
   4.0
   8.0
  16.0
  32.0
  64.0
```

## Rows and columns

The vectors so far are *columns*: their numbers stand one below the other.
Separating the numbers with commas instead of semicolons makes a *row*,
which Axon treats as a matrix with one row. `'` turns a column into a row
and a row into a column:

```repl
> [1, 2, 3]
1×3 matrix{int}
  1  2  3
> x = [1; 2; 3]
x = 3-vector{int}
  1
  2
  3
> x'
1×3 matrix{int}
  1  2  3
```

For a list of values, use a column, written with semicolons. Rows come into
their own in matrices.

## Matrices

A matrix is a table of numbers. Its rows are separated by semicolons and the
numbers in each row by commas:

```repl
> A = [1, 2, 3; 4, 5, 6]
A = 2×3 matrix{int}
  1  2  3
  4  5  6
> size(A)
2
3
> A[2, 1]
4
> A[2, :]
3-vector{int}
  4
  5
  6
> A[:, 2]
2-vector{int}
  2
  5
```

`size` gives the numbers of rows and columns. An element has two positions,
row first: `A[2, 1]` is in the second row and the first column. A colon on
its own means "all of them", so `A[2, :]` is the whole second row and
`A[:, 2]` the whole second column.

Matrices suit tables of measurements, with one row per sample and one
column per quantity. Here are temperatures taken three times a day for four
days; a long matrix can be written over several lines, one row per line:

```axon
# readings.sci: three readings a day, for four days
readings = [12.1, 15.3, 13.0;
            11.8, 16.0, 12.4;
            13.5, 17.2, 14.1;
            12.9, 15.8, 13.3]
[days, times] = size(readings)
for d in 1:days
  println("Day", d, "mean", format(mean(readings[d, :]), 2))
end
println("Afternoon mean:", format(mean(readings[:, 2]), 2))
println("Highest:", max(readings))
```

```output
Day 1 mean 13.47
Day 2 mean 13.40
Day 3 mean 14.93
Day 4 mean 14.00
Afternoon mean: 16.07
Highest: 17.2
```

`[days, times] = size(readings)` keeps both of the sizes, as in Lesson 3.
`mean(readings[d, :])` is the mean of one day's row, and
`mean(readings[:, 2])` the mean of the afternoon column. `max` of the whole
matrix is its largest element.

## Solving equations

Matrices make it easy to solve several equations at once. A chemist needs
10 litres of a 25% acid solution, and has a 10% solution and a 30% one. If
`x` litres of the first are mixed with `y` litres of the second, then

```text
x + y = 10              (litres in total)
0.1 x + 0.3 y = 2.5     (litres of acid)
```

The numbers in front of `x` and `y` form a matrix, one row per equation,
and the right-hand sides a vector. `\` solves the equations:

```axon
# mixing.sci: how much of each solution?
M = [1.0, 1.0;
     0.1, 0.3]
rhs = [10.0; 2.5]
amounts = M \ rhs
println(amounts)
```

```output
2-vector{real}
  2.5
  7.5
```

So 2.5 litres of the 10% solution and 7.5 litres of the 30% one. `M \ rhs`
reads as "divide `rhs` by `M` from the left": it finds the vector that `M`
multiplies to give `rhs`. The same works for any number of equations with
as many unknowns.

## Mistakes

Element-by-element operations need vectors of the same length:

```repl
> [1; 2; 3] + [1; 2]
DimensionError: operator +: cannot broadcast a 3-vector with a 2-vector
  at <repl>:1:1
```

And `*` between two vectors, where `.*` was meant:

```repl
> heights * heights
DimensionError: matrix product: a 4-vector times a 4-vector (inner sizes 1 and 4 differ)
  at <repl>:1:1
```

The quiet mistake is the worst: `/` or `^` without the dot between vectors
gives an answer, but not the one you wanted. If a result has an unexpected
size, look for a missing dot.

## Summary

- `[a; b; c]` is a vector (a column); `[a, b; c, d]` is a matrix, with
  rows separated by semicolons.
- `v[k]` is the element at position `k`, from 1; `v[end]` is the last, and
  `v[2:4]` several. `A[i, j]` is row `i`, column `j`; `A[i, :]` is a whole
  row and `A[:, j]` a whole column.
- `length`, `size`, `sum`, `mean`, `max`, `min` and `sort` work on whole
  vectors and matrices.
- Arithmetic with a single number, and `+` and `-` between equal sizes, work
  element by element; for `*`, `/` and `^` element by element, use `.*`,
  `./` and `.^`.
- `linspace(a, b, n)`, `zeros(n)` and `ones(n)` make vectors; so does
  calculating with a range. A loop can fill a vector made with `zeros`.
- `M \ b` solves the equations whose numbers are the rows of `M`.

## Exercises

1. Add up the squares of the whole numbers from 1 to 10 without a loop.
   (Lesson 2 did it with one: the answer is 385.)
2. The function `celsius` from Lesson 3 uses only `-`, `*` and `/` with
   single numbers, so it works on a vector too. Use it to convert the
   temperatures 32, 50, 77, 98.6 and 212 degrees Fahrenheit in one call.
3. In the Fibonacci sequence, the first two numbers are 1 and each later
   one is the sum of the two before it. Fill a vector with the first ten.
4. Three students took four tests. The first student's marks were 62, 75,
   80 and 71; the second's 88, 92, 79 and 95; the third's 55, 60, 68 and
   72. Store the marks in a matrix, one row per student, and print the mean
   mark of each student, the mean mark of each test, and the highest mark.
5. Solve the three equations x + y + z = 6, 2y + 5z = -4 and
   2x + 5y - z = 27.
6. In `bmi_all.sci`, which person has the highest index? Write a loop that
   finds the position of the largest element of `bmi`.

## Answers

**Exercise 1.**

```repl
> sum((1:10).^2)
385
```

**Exercise 2.** The same function works for one temperature or many:

```axon
# celsius_all.sci: converting several temperatures at once

## The temperature f, in degrees Fahrenheit, in degrees Celsius.
function celsius(f)
  return (f - 32) * 5 / 9
end

println(celsius([32.0; 50.0; 77.0; 98.6; 212.0]))
```

```output
5-vector{real}
    0.0
   10.0
   25.0
   37.0
  100.0
```

**Exercise 3.** Each element after the second is worked out from the two
before it:

```axon
# fibonacci.sci: the first ten Fibonacci numbers
fib = zeros(10)
fib[1] = 1
fib[2] = 1
for k in 3:10
  fib[k] = fib[k - 1] + fib[k - 2]
end
println(fib)
```

```output
10-vector{real}
   1.0
   1.0
   2.0
   3.0
   5.0
   8.0
  13.0
  21.0
  34.0
  55.0
```

**Exercise 4.** One row per student, one column per test:

```axon
# marks.sci: means by student and by test
marks = [62, 75, 80, 71;
         88, 92, 79, 95;
         55, 60, 68, 72]
for s in 1:3
  println("Student", s, format(mean(marks[s, :]), 1))
end
for test in 1:4
  println("Test", test, format(mean(marks[:, test]), 1))
end
println("Highest:", max(marks))
```

```output
Student 1 72.0
Student 2 88.5
Student 3 63.8
Test 1 68.3
Test 2 75.7
Test 3 75.7
Test 4 79.3
Highest: 95
```

**Exercise 5.** The second equation has no `x`, so its first number is 0:

```axon
# system.sci: three equations in three unknowns
S = [1.0, 1.0, 1.0;
     0.0, 2.0, 5.0;
     2.0, 5.0, -1.0]
println(S \ [6.0; -4.0; 27.0])
```

```output
3-vector{real}
   5.0
   3.0
  -2.0
```

So x = 5, y = 3 and z = -2.

**Exercise 6.** Keep the position of the largest element seen so far, and
compare each later element with it:

```axon
# highest.sci: who has the highest body mass index?
masses = [55.0; 72.0; 80.0; 61.0]     # kg
heights = [1.62; 1.75; 1.80; 1.68]    # m
bmi = masses ./ heights.^2
best = 1
for k in 2:length(bmi)
  if bmi[k] > bmi[best]
    best = k
  end
end
println("Person", best, "has the highest index:", format(bmi[best], 1))
```

```output
Person 3 has the highest index: 24.7
```

Next: [Lesson 5: Plotting](tutorial-05-plotting.md)
