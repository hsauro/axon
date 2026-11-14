# The Axon tutorial

[Contents](index.md)

This tutorial teaches programming with Axon to scientists who have done
little or no programming before. It is a series of short lessons, each of
about ten to fifteen minutes. Work through them in order: each lesson uses
what the earlier ones taught.

## How to use the lessons

- In the IDE, **Help > Tutorial** opens the lessons in the Documentation
  tab. Click **Open in Window** at the top right of that tab to move them
  to a window of their own. Put the window beside the IDE or on a second
  screen, so that the lesson stays in view while you work in the editor and
  in the **REPL** tab.
- Type the examples yourself rather than copying them. Typing is how the
  rules of the language stick, and the small mistakes you make on the way
  teach as much as the examples do.
- Every example shows what Axon answers or prints, so you can check your
  result against it.
- Each lesson ends with exercises, followed by their answers. Try each
  exercise before you look.

The examples come in three kinds of box. A REPL session shows lines that
start with `>`: type what follows the `>` and press <kbd>Enter</kbd>, and the
lines under it are Axon's answer.

```repl
> 2 + 3
5
```

The REPL sessions in a lesson follow on from each other, as your REPL does:
a variable made in one box is used in later ones. If you restart the REPL
part way through a lesson, type the earlier lines again.

A program is a file you type in the editor and run with <kbd>F9</kbd>:

```axon
println("Hello")
```

The box after a program shows what it prints in the **Output** tab:

```output
Hello
```

## The lessons

1. [First steps](tutorial-01-first-steps.md): the REPL, arithmetic, whole
   and real numbers, mathematical functions, variables and a first program.
2. [Decisions and repetition](tutorial-02-decisions.md): true and false,
   `if`, `for` and `while` loops, adding up in a loop, and looking at a
   program's variables in the REPL.
3. [Writing your own functions](tutorial-03-functions.md): parameters and
   `return`, documentation comments, variables inside functions, optional
   and keyword arguments, returning two values, and `error`.
4. [Vectors and matrices](tutorial-04-vectors.md): making vectors,
   picking out elements, calculating element by element, tables of data
   in matrices, and solving equations with `\`.
5. [Plotting](tutorial-05-plotting.md): line plots, measured data with a
   model, bar charts, histograms, plots side by side, saving figures, and
   the Plot pane.
6. [Text and files](tutorial-06-text-files.md): strings, splitting text
   and reading numbers from it, writing and reading text files, a report in
   columns, and tables of numbers in CSV files.
