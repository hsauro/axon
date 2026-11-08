# Getting started

[Contents](index.md)

## Your first program

In the IDE, choose **File > New** (<kbd>Ctrl+N</kbd>), type a program and press
<kbd>F9</kbd> to run it. The IDE asks you to save the file first; Axon files end
in `.sci`.

```axon
println("Hello, world")
A = [1, 2; 3, 4]
println(A * A)
```

The output appears in the **Output** pane. If the program stops with an error,
the error is shown in red, the line is underlined in the editor, and the trace
lines below the error are links: click one to go to that line.

From a terminal, the same program runs with

```
axon hello.sci
```

## Trying things out: the REPL

The **REPL** tab at the bottom of the IDE runs one statement at a time and keeps
your variables between statements. Type an expression and press
<kbd>Enter</kbd>; its value is shown straight away. A statement that continues
over several lines, such as a function, shows a `...` prompt until it is
complete. <kbd>Up</kbd> and <kbd>Down</kbd> recall earlier lines.

In the editor, <kbd>Ctrl+Enter</kbd> sends the current line (or the selection)
to the REPL, which is a quick way to try part of a program.

Running `axon` with no file starts the same REPL in a terminal.

## Finding help

- Put the caret on a name, such as `sin` or `ode.solve`, and press <kbd>F1</kbd>.
  The **Help** pane shows its parameters and description. This works for the
  built-in functions, for the functions of modules you import, and for functions
  you write yourself with a `##` comment above them.
- In the REPL, `help name` does the same, and `help` alone lists the commands.
- **Help > Documentation** opens these pages, and **Help > Language Reference**
  the complete description of the language.

Documentation comments start with `##` and sit directly above a function:

```axon
## The area of a circle of radius r.
function area(r)
  return 3.141592653589793 * r^2
end
println(area(2.0))
```

## Plots

`plot.line`, `plot.scatter` and `plot.surface` build a figure; `plot.show()`
displays it in the IDE's **Plot** pane (or in your image viewer when you run
from a terminal), and `plot.save("figure.pdf")` writes a PNG, SVG or PDF file.

```axon
import plot
x = linspace(0.0, 6.283, 100)
plot.line(x, sin(x), label = "sin")
plot.line(x, cos(x), label = "cos", style = "--")
plot.title("Two waves")
plot.show()
```

## Next steps

- [A tour of Axon](tour.md) covers the whole language briefly.
- The examples on the welcome screen are complete programs to change and run.
- [Using the IDE](ide.md) lists every shortcut.
