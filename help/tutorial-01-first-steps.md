# Lesson 1: First steps

[Tutorial](tutorial.md)

In this lesson you use Axon as a calculator. You meet the REPL, where Axon
answers one line at a time; arithmetic; the two kinds of number, whole and
real; some mathematical functions; variables, which give values names; and
your first program.

## The REPL

At the bottom of the IDE is a tab called **REPL**. Click it, then click in
the box at its bottom, next to the `>` sign. Type `2 + 3` and press
<kbd>Enter</kbd>. Axon works out the value and shows it:

```repl
> 2 + 3
5
```

REPL stands for read, evaluate, print, loop: it reads what you type, works
out (evaluates) its value, prints it, and waits for the next line. In these
lessons a REPL session is shown like the one above: the lines that start
with `>` are what you type, without the `>`, and the lines under each are
Axon's answer.

Press <kbd>Up</kbd> to bring back the line you typed last; change it and
press <kbd>Enter</kbd> again. This saves a lot of typing.

## Arithmetic

Axon uses `+` and `-` for adding and subtracting, `*` for multiplying, `/`
for dividing and `^` for powers:

```repl
> 7 * 6
42
> 7 / 2
3.5
> 2 ^ 10
1024
> 2 - 3 * 4
-10
```

As in ordinary mathematics, powers are worked out first, then
multiplication and division, then addition and subtraction, so `2 - 3 * 4`
is `2 - 12`. Brackets change the order:

```repl
> (2 - 3) * 4
-4
> 1 + 2 * 3
7
> (1 + 2) * 3
9
```

The spaces around the operators are optional: `2-3*4` means the same as
`2 - 3 * 4`, but the spaces make it easier to read.

## Whole numbers and real numbers

Axon has two kinds of number. A whole number, such as `42` or `-7`, is an
*integer*. A number with a decimal point, such as `3.5` or `2.0`, is a
*real* number. `typeof` tells you which kind a value is:

```repl
> typeof(42)
"int"
> typeof(3.5)
"real"
```

Adding, subtracting and multiplying integers gives an integer. Dividing
with `/` always gives a real number, even when the answer is whole:

```repl
> 6 / 3
2.0
> 10 / 3
3.33333333333333
```

To divide whole numbers, `div` gives the whole part of the answer and `mod`
the remainder. 17 divided by 5 is 3, with 2 left over:

```repl
> div(17, 5)
3
> mod(17, 5)
2
```

Very large and very small numbers are written with an `e`, which means
"times ten to the power of": `1e6` is a million and `2.5e-3` is 0.0025.

```repl
> 1e6
1000000.0
> 2.5e-3
0.0025
```

Real numbers are shown with up to 15 significant digits. A computer stores
a real number to about 16 digits, so the last digit of a long result may be
rounded.

## Mathematical functions

Axon knows the usual mathematical functions. The name of a function is
followed by its *argument*, the value it works on, in brackets:

```repl
> sqrt(16)
4.0
> sqrt(3^2 + 4^2)
5.0
> exp(1)
2.71828182845905
> log(100)
4.60517018598809
> log10(100)
2.0
> sin(pi / 2)
1.0
```

`log` is the natural logarithm and `log10` the logarithm to base 10. Angles
are in radians, and `pi` is the number pi. `sqrt` always gives a real
number, even for a perfect square such as 16.

To find out what a function does, type `help` and its name:

```repl
> help sqrt
sqrt(x)
  The square root (NaN for a negative real; use a complex argument)
```

In the editor, you can instead put the caret on a name and press
<kbd>F1</kbd>.

## Variables

A *variable* gives a value a name, so that you can use it again. `=` stores
the value on its right under the name on its left:

```repl
> r = 2.5
r = 2.5
> area = pi * r^2
area = 19.6349540849362
> area
19.6349540849362
> 2 * area
39.2699081698724
```

The REPL shows each value as it is stored. After that, the name can be used
wherever its value could.

`=` does not mean "equals" as it does in mathematics: it means "store". So
`x = x + 1` makes sense. It works out `x + 1` with the value `x` has now,
and stores the result back in `x`:

```repl
> x = 10
x = 10
> x = x + 1
x = 11
```

A name is made of letters, digits and underscores, and starts with a
letter: `r`, `area`, `growth_rate` and `x2` are all names. Capital letters
count, so `Area` and `area` are different names. Choose names that say what
a value is: `growth_rate` is clearer than `g`.

## Mistakes

Everybody makes mistakes when programming, and Axon tells you what went
wrong. Here a name is used before it has a value:

```repl
> speed * 2
NameError: "speed" is not defined
  at <repl>:1:1
```

The first word says what kind of mistake it is, and the rest of the line
explains it. `1:1` gives the line and the column where it happened. Nothing
is broken: correct the line and try again. Two more:

```repl
> 2x
SyntaxError: expected end of line or ";", found identifier "x"
  at <repl>:1:2
> 3 + "three"
TypeError: operator + is not defined for int and string
  at <repl>:1:1
```

A `SyntaxError` means that Axon could not read the line: multiplication must
be written out, as `2 * x`. A `TypeError` means that the values do not suit
the operation: a number cannot be added to a piece of text.

## A first program

The REPL forgets everything when it is restarted. A *program* is a file of
lines that Axon runs from top to bottom, and you can run it again whenever
you like.

Choose **File > New** (<kbd>Ctrl+N</kbd>) and type:

```axon
# circle.sci: the area of a circle
r = 2.5
area = pi * r^2
println("The area is", area)
```

Press <kbd>F9</kbd> to run it. The IDE asks you to save the file first: call
it `circle.sci` (Axon programs end in `.sci`). What the program prints
appears in the **Output** tab:

```output
The area is 19.6349540849362
```

The first line is a *comment*: Axon skips everything from a `#` to the end
of the line, so you can write notes for yourself and for other readers.

A program does not show values as the REPL does; `println` prints them. It
prints each of its arguments with a space between them, and then ends the
line. Text in double quotes, such as `"The area is"`, is printed as it is.

Fifteen digits are more than anyone needs here. `format(area, 2)` gives the
number as text with two decimals. Change the last line and run the program
again:

```axon
# circle.sci: the area of a circle
r = 2.5
area = pi * r^2
println("The area is", format(area, 2))
```

```output
The area is 19.63
```

Now change `r` to another value and press <kbd>F9</kbd> once more. Changing a
program and running it again is how you explore a calculation.

## Summary

- The REPL works out each line as you type it. A program is a file that
  runs from top to bottom when you press <kbd>F9</kbd>.
- `+`, `-`, `*`, `/` and `^` do arithmetic, and brackets set the order.
- Integers are whole numbers; reals have a decimal point. `/` always gives
  a real number; `div` and `mod` divide whole numbers.
- Functions such as `sqrt`, `exp`, `log` and `sin` take their argument in
  brackets, and `pi` is pi. `help name` explains a function.
- `name = value` stores a value under a name.
- In a program, `println` prints, and `format(x, d)` gives `x` with `d`
  decimals.
- An error message names the kind of mistake and where it happened.

## Exercises

1. How many seconds are there in a year of 365 days?
2. A right-angled triangle has sides of 3 cm and 4 cm next to the right
   angle. How long is the third side? (By Pythagoras, it is the square root
   of 3 squared plus 4 squared.)
3. Normal body temperature is 98.6 degrees Fahrenheit. In degrees Celsius
   that is 98.6 minus 32, times 5, divided by 9. Work it out.
4. What are `div(23, 7)` and `mod(23, 7)`? Check that 7 times the first,
   plus the second, is 23.
5. Write a program `sphere.sci` that stores a radius of 2 in `r` and prints
   the volume of a sphere of that radius, four thirds of pi times `r`
   cubed, with three decimals.

## Answers

**Exercise 1.** Multiply the days by the hours in a day, the minutes in an
hour and the seconds in a minute: about 31.5 million seconds.

```repl
> 365 * 24 * 60 * 60
31536000
```

**Exercise 2.** 5 cm.

```repl
> sqrt(3^2 + 4^2)
5.0
```

**Exercise 3.** 37 degrees Celsius. The brackets matter: without them,
only 32 would be multiplied by 5 and divided by 9.

```repl
> (98.6 - 32) * 5 / 9
37.0
> 98.6 - 32 * 5 / 9
80.8222222222222
```

**Exercise 4.** 23 divided by 7 is 3, with 2 left over.

```repl
> div(23, 7)
3
> mod(23, 7)
2
> 7 * 3 + 2
23
```

**Exercise 5.**

```axon
# sphere.sci: the volume of a sphere
r = 2
volume = 4 / 3 * pi * r^3
println("The volume is", format(volume, 3))
```

```output
The volume is 33.510
```

Next: [Lesson 2: Decisions and repetition](tutorial-02-decisions.md)
