# Lesson 5: Plotting

[Tutorial](tutorial.md)

A column of numbers hides what a picture shows at once: a trend, a peak,
a point that does not fit. This lesson draws line plots of functions,
measured data with a model through it, bar charts and histograms, and
several plots side by side, and shows how to label and save them.

## A first plot

```axon
# sine.sci: one period of a sine wave
import plot
x = linspace(0, 2 * pi, 100)
y = sin(x)
plot.line(x, y)
plot.show()
```

Run it with <kbd>F9</kbd>. The plot appears in the **Plot** pane at the
right of the IDE.

The first line after the comment, `import plot`, loads the `plot` *module*:
a collection of functions for drawing, which is not loaded until a program
asks for it. Its functions are called with `plot.` in front of their names.

`x` holds 100 evenly spaced values from 0 to 2 pi, and `y` the sine of each
(`sin` works on a whole vector, as Lesson 4 showed). `plot.line(x, y)` joins
the points (x, y) with straight lines; with 100 points close together, they
look like a smooth curve. Try `linspace(0, 2 * pi, 8)` to see the corners.
`plot.show()` displays the figure.

## Titles, labels and a legend

A plot is only useful if the reader knows what it shows. `plot.title`,
`plot.xlabel` and `plot.ylabel` add a title and name the axes. Several
`plot.line` calls draw several lines on the same axes, each in its own
colour, and a `label` names a line in the legend:

```axon
# waves.sci: two waves, labelled
import plot
x = linspace(0, 2 * pi, 100)
plot.line(x, sin(x), label = "sin x")
plot.line(x, cos(x), label = "cos x", style = "--")
plot.title("Two waves")
plot.xlabel("x (radians)")
plot.ylabel("y")
plot.show()
```

`label` and `style` are keyword arguments, as in Lesson 3: given by name,
and left out when the default will do. `style` can be `"-"` (a solid line,
the default), `"--"` (dashed), `":"` (dotted) or `"-."`. `color` chooses the
colour, such as `color = "red"`; the colours by name are black, red, green,
blue, orange, purple, brown, pink, gray, olive, cyan and yellow. `width`
sets the thickness of the line.

## Measured data and a model

Measurements are best drawn as separate points, with `plot.scatter`, and a
model through them as a line. Here are the rates of an enzyme reaction
measured at six substrate concentrations, with the Michaelis-Menten curve of
Lesson 3:

```axon
# enzyme.sci: measured rates and the Michaelis-Menten curve
import plot

## The rate of an enzyme reaction at substrate concentration s.
function rate(s; vmax = 10.0, km = 2.0)
  return vmax * s ./ (km + s)
end

s_data = [0.5; 1.0; 2.0; 4.0; 6.0; 10.0]
v_data = [2.1; 3.4; 4.9; 6.8; 7.4; 8.4]
s = linspace(0, 10, 100)
plot.scatter(s_data, v_data, label = "measured")
plot.line(s, rate(s), label = "model")
plot.title("Enzyme kinetics")
plot.xlabel("substrate concentration (mM)")
plot.ylabel("rate")
plot.show()
```

Look at `rate`: it divides with `./`, not `/` as in Lesson 3. Here it is
given the whole vector `s`, and `./` divides element by element. With `/`,
the function would still work for a single number but would quietly give a
wrong result for a vector, as Lesson 4 warned. A dotted operator works for
single numbers too, so a function written with `.*`, `./` and `.^` works for
both.

## Bar charts

`plot.bar` draws a bar for each value. Its first argument can be the names
of the bars, in curly brackets:

```axon
# rainfall.sci: rainfall by month
import plot
months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun"}
rain = [78.0; 61.0; 55.0; 47.0; 52.0; 40.0]
plot.bar(months, rain)
plot.title("Rainfall")
plot.ylabel("mm")
plot.show()
```

The curly brackets make a *list*, which can hold text as well as numbers;
Lesson 7 says more about lists.

## Histograms

A histogram shows how a set of values is spread out: it divides their range
into intervals, called bins, and draws a bar for each, as high as the
number of values in it. This program makes 500 heights at random, from a
normal distribution with a mean of 170 cm and a standard deviation of 8 cm,
using the `random` module:

```axon
# heights.sci: a histogram of 500 random heights
import plot
import random
random.seed(1)
heights = random.normal(170.0, 8.0, 500)
plot.hist(heights, bins = 20)
plot.title("500 heights")
plot.xlabel("height (cm)")
plot.ylabel("number of people")
plot.show()
println("Mean:", format(mean(heights), 1))
```

```output
Mean: 170.2
```

`random.seed(1)` starts the random numbers at a fixed point, so the program
makes the same numbers every time it runs; without it, every run differs.

## Plots side by side

`plot.subplot(rows, columns, k)` divides the figure into a grid and makes
cell `k` the current one: the plotting that follows goes into it. Cells are
numbered along each row, from the top left.

```axon
# damped.sci: a damped oscillation and its envelope
import plot
t = linspace(0, 10, 200)
plot.subplot(1, 2, 1)
plot.line(t, exp(-0.3 * t) .* cos(2 * t))
plot.title("Damped oscillation")
plot.xlabel("time (s)")
plot.subplot(1, 2, 2)
plot.line(t, exp(-0.3 * t))
plot.title("Its envelope")
plot.xlabel("time (s)")
plot.show()
```

## Saving a figure

`plot.save` writes the current figure to a file, in the program's folder.
The file name's ending chooses the format: `.png` for a picture, `.pdf` or
`.svg` for a drawing that stays sharp at any size, for papers and reports.

```axon
# saving.sci: a figure saved as a file
import plot
x = linspace(0, 2 * pi, 100)
plot.line(x, sin(x))
plot.title("Saved")
plot.save("saved.png")
println("Saved saved.png")
```

```output
Saved saved.png
```

The Plot pane can save too: its **Save...** button writes the figure you are
looking at, and **Copy** puts it on the clipboard, to paste into a document.

## The Plot pane

The Plot pane is more than a picture. In a line, scatter, bar or histogram
plot:

| Action | Effect |
| --- | --- |
| Mouse wheel | Zoom in or out around the pointer |
| Drag | Move the plot |
| <kbd>Ctrl</kbd>+double-click | Back to the whole plot |
| Double-click | Change the titles, axes, line styles and legend |
| Click a legend entry | Hide or show that line |

The pane keeps the figures of earlier runs: **◀** and **▶** in its header
step back and forward through them, so you can compare a plot with the one
before a change.

## Starting a new figure

A program starts with an empty figure, and everything it plots goes into
it. `plot.show()` shows the figure but does not clear it: plotting after it
adds to the same figure. To draw a second, separate figure, start one with
`plot.new()`:

```axon
# two.sci: two separate figures
import plot
x = linspace(0, 2 * pi, 100)
plot.line(x, sin(x))
plot.title("First figure")
plot.show()
plot.new()
plot.line(x, x.^2)
plot.title("Second figure")
plot.show()
```

Both figures appear in the Plot pane; **◀** goes back to the first. The same
applies in the REPL, where the figure lasts as long as the session: use
`plot.new()` before plotting something unrelated.

## Mistakes

Forgetting `import plot`:

```axon
# noimport.sci
x = linspace(0, 1, 5)
plot.line(x, x)
```

```output
NameError: "plot" is not defined
  at noimport.sci:3:1
```

Giving `x` and `y` different numbers of values stops with an error such as
`DimensionError: plot.line: x has 5 values but y has 3`. Each point needs
both of its coordinates.

And a function written with `/` or `^` instead of `./` or `.^`, given a
vector: the result is not one value per point, and the plot fails or comes
out wrong. Use the dotted operators in functions you plot.

## Summary

- `import plot` loads the plotting functions; they are called as
  `plot.line`, `plot.show` and so on.
- `plot.line(x, y)` draws a line through the points, `plot.scatter(x, y)`
  separate points, `plot.bar(names, values)` bars, and
  `plot.hist(values, bins = n)` a histogram.
- `label`, `style`, `color` and `width` change a line; `plot.title`,
  `plot.xlabel` and `plot.ylabel` label the figure.
- `plot.subplot(rows, columns, k)` puts several plots side by side.
- `plot.show()` shows the figure in the Plot pane; `plot.save("name.png")`
  (or `.pdf`, `.svg`) saves it; `plot.new()` starts a new figure.
- Functions to be plotted should use `.*`, `./` and `.^`.

## Exercises

1. Plot y = x squared for x from -3 to 3, with a title and labelled axes.
2. Write the logistic function of Lesson 3 with dotted operators, and plot
   the population from t = 0 to 20 for growth rates 0.5 and 1.0 on the same
   axes, with a legend.
3. Plot the drug's concentration from Lesson 4 over 48 hours, with a
   marker at each of the nine time points. (`plot.line` takes
   `marker = "circle"`.)
4. Draw a bar chart of the mean marks of the three students in Lesson 4,
   exercise 4. Name the bars `"A"`, `"B"` and `"C"`.
5. Draw sin x and cos x for x from 0 to 2 pi one above the other, in a grid
   of two rows and one column.

## Answers

**Exercise 1.** `x.^2` squares each element:

```axon
# square.sci: y = x squared
import plot
x = linspace(-3, 3, 100)
plot.line(x, x.^2)
plot.title("y = x squared")
plot.xlabel("x")
plot.ylabel("y")
plot.show()
```

**Exercise 2.** `k ./ (...)` divides a single number by each element:

```axon
# logistic_plot.sci: logistic growth at two rates
import plot

## The size at time t of a population that grows logistically.
function logistic(t; n0 = 10.0, r = 0.5, k = 1000.0)
  return k ./ (1 + (k / n0 - 1) * exp(-r * t))
end

t = linspace(0, 20, 200)
plot.line(t, logistic(t), label = "r = 0.5")
plot.line(t, logistic(t, r = 1.0), label = "r = 1.0")
plot.title("Logistic growth")
plot.xlabel("time")
plot.ylabel("population")
plot.show()
```

**Exercise 3.**

```axon
# decay_plot.sci: a drug's concentration over two days
import plot
t = linspace(0, 48, 9)
c = 100 * 0.5 .^ (t / 6)
plot.line(t, c, marker = "circle")
plot.title("Drug concentration")
plot.xlabel("time (hours)")
plot.ylabel("concentration (mg/L)")
plot.show()
```

**Exercise 4.** The mean of each row of the marks matrix, filled into a
vector:

```axon
# marks_plot.sci: mean marks as a bar chart
import plot
marks = [62, 75, 80, 71;
         88, 92, 79, 95;
         55, 60, 68, 72]
means = zeros(3)
for s in 1:3
  means[s] = mean(marks[s, :])
end
plot.bar({"A", "B", "C"}, means)
plot.title("Mean marks")
plot.ylabel("mark")
plot.show()
```

**Exercise 5.**

```axon
# sincos.sci: two plots, one above the other
import plot
x = linspace(0, 2 * pi, 100)
plot.subplot(2, 1, 1)
plot.line(x, sin(x))
plot.title("sin x")
plot.subplot(2, 1, 2)
plot.line(x, cos(x))
plot.title("cos x")
plot.show()
```

Next: [Lesson 6: Text and files](tutorial-06-text-files.md)
