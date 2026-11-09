# Using the IDE

[Contents](index.md)

## The window

| Area | What it shows |
| --- | --- |
| Editor tabs | Your files, with syntax colouring and line numbers. The **Welcome** tab lists recent files and the examples. Close a tab with the × at its right end, a middle-click, or <kbd>Ctrl+W</kbd> (<kbd>Cmd+W</kbd> on a Mac). |
| Plot pane (right) | The latest figure from `plot.show()`, or the newest PNG a run saved. |
| Output | What a program prints, and its errors in red. |
| REPL | An interactive session that keeps its variables. |
| Help | Help on the word under the caret (<kbd>F1</kbd>). |

The panes can be resized by dragging their edges. The IDE remembers the window
and pane sizes, and the recent files, between sessions.

## Running programs

<kbd>F9</kbd> saves the current file and runs it with `axon`, in the file's own
folder, so `import` finds modules next to it and files the program writes land
there. **Stop** (<kbd>Ctrl+F2</kbd>) ends a program that runs too long.

While you type, the IDE checks the syntax: about half a second after you stop,
a syntax error gets a wavy red underline, and hovering it shows the message.

When a program stops with an error, the error's line is underlined in the
editor and the caret moves there. In the Output pane, each trace line
(`at file:line:col`) is a link to that place.

The grey lines in the Output pane are the IDE's own notes: *Running …* and
*Finished in …* around each run, and the JIT report after it. To hide
them, untick **Show run notes** or **Show JIT report** in
**Edit > Preferences**. Errors and the program's own output always show.

## Compiled and interpreted

Functions are compiled to native code at their first call, which makes
loops and recursive functions hundreds of times faster. The **JIT** button
in the toolbar (or **Run > Use JIT Compiler**) switches this off and on, so
you can run the same program both ways and compare: the results are the
same, only the time differs. The *JIT: compiled and interpreted* example
on the welcome screen is made for this.

After a run with the JIT on, the Output pane lists the functions that were
compiled, and for those that ran interpreted, the reason, such as a
variable whose type changes or an argument that is a string. The REPL
follows the setting when it starts: use **Run > Restart REPL** after
switching.

How much faster? These are Axon's benchmarks (`bench/run.sci` in the
source tree), each the best of five runs on a desktop PC (Intel Core
i9-9900X), with identical results both ways:

| Program | Interpreted | Compiled | Faster |
| --- | --- | --- | --- |
| Recursive `fib(22)` | 132 ms | 222 µs | 595× |
| A sum loop, 100,000 terms | 89 ms | 106 µs | 841× |
| Sieve of Eratosthenes to 100,000 | 375 ms | 724 µs | 517× |
| Mandelbrot set, 60 × 60 points | 190 ms | 212 µs | 896× |
| 60 × 60 matrix product, written as loops | 462 ms | 411 µs | 1123× |
| N-body, 1000 steps | 210 ms | 302 µs | 695× |
| `ode.solve` with `rk45` (Lotka–Volterra) | 22.6 ms | 5.63 ms | 4× |
| `ode.solve` with `bdf` (Robertson) | 4.79 ms | 1.13 ms | 4× |

The ODE solvers' own loops are native either way, so there the JIT speeds
up only the right-hand side `f`. Compilation itself happens once, at the
first call, and takes about a millisecond. For matrix work, the built-in
operators are faster still: `A * B` on the same 60 × 60 matrices takes
36 µs, because it calls an optimised BLAS library.

## The REPL pane

Type a statement and press <kbd>Enter</kbd>. A session starts the first time
you use it, in the current file's folder, and keeps its variables until you
press **Restart**, which also stops a statement that does not finish. **Clear**
empties the transcript.

**Run** (<kbd>F9</kbd>) runs a program on its own, and its variables are gone
when it ends. To keep them, use the **▶ REPL** button next to Run (or
**Run > Run in REPL**, <kbd>Shift+F9</kbd>): it saves the file and runs it in
the REPL session, so afterwards you can inspect any of its variables there,
such as `sol.t` or `A`. Its output appears in the REPL pane, assignments in the
file are not displayed, and the variables stay until you press **Restart**.
At the prompt, `run "file.sci"` does the same for any file.

## Plots

`plot.show()` displays the current figure in the plot pane at once, even while
the program is still running. Without it, the figure is shown when the program
ends. Figures saved with `plot.save("name.png")` are
shown too, when the program ends.

Line, scatter, bar and histogram plots are shown in an interactive chart:

| Action | Effect |
| --- | --- |
| Mouse wheel | Zoom in or out around the pointer |
| Drag | Pan |
| <kbd>Shift</kbd>+drag | Zoom to the box you draw |
| <kbd>Ctrl</kbd>+double-click | Back to the whole plot |
| Double-click | Edit titles, axes, series styles and the legend |
| Click a legend entry | Hide or show that series |
| Right-click | Copy the image, or export it as PNG or PDF |

3D plots (`plot.surface`, `plot.line3`, `plot.scatter3`) are shown in an
interactive 3D chart:

| Action | Effect |
| --- | --- |
| Drag | Rotate |
| Right-drag, or <kbd>Shift</kbd>+drag | Pan |
| Mouse wheel | Zoom |
| Hover | Show the coordinates of the nearest point |
| Double-click | Edit titles, axes, series styles, lighting and the legend |
| <kbd>Ctrl</kbd>+double-click | Back to the starting view |
| Arrow keys, <kbd>+</kbd>/<kbd>-</kbd>, <kbd>R</kbd>, <kbd>1</kbd>–<kbd>4</kbd> | Rotate, zoom, reset, preset views (isometric, top, front, side) |
| Right-click | Copy the image, export PNG or PDF, and more |

## Help

<kbd>F1</kbd> shows help on the name under the caret: a built-in function, a
function from an imported module (`ode.solve`, or `solve` after
`from linalg import solve`), or a function or record defined in the file with a
`##` comment above it.

Below the short description, the Help pane shows the section of the Language
Reference that documents the name, when there is one: the whole module's
section for a module function such as `ode.solve` (keywords, result, events,
errors), and for built-ins such as `println` or `zeros` the section that covers
them. Its last link opens that section in the Documentation tab.

**Edit > Preferences** sets the text size of the Documentation tab
(**Documentation font size**) and of the Help pane (**Output font size**).

## Shortcuts

| Key | Action |
| --- | --- |
| <kbd>F9</kbd> | Run the current file |
| <kbd>Shift+F9</kbd> | Run the current file in the REPL, keeping its variables there |
| <kbd>Ctrl+F2</kbd> | Stop the running program |
| <kbd>Ctrl+Enter</kbd> | Send the current line or selection to the REPL |
| <kbd>F1</kbd> | Help on the word under the caret |
| <kbd>Ctrl+N</kbd>, <kbd>Ctrl+O</kbd>, <kbd>Ctrl+S</kbd> | New, open, save |
| <kbd>Shift+Ctrl+S</kbd> | Save as |
| <kbd>Ctrl+W</kbd> | Close the current tab |
| <kbd>Ctrl+F</kbd> | Find and replace; in the Documentation tab, find in the page (Enter / Shift+Enter for next / previous, Escape to close) |
| <kbd>Ctrl+G</kbd> | Go to line |
| <kbd>Ctrl+/</kbd> | Comment or uncomment the selected lines |
| <kbd>Ctrl+Z</kbd>, <kbd>Ctrl+Y</kbd> | Undo, redo |

On macOS, use <kbd>Cmd</kbd> in place of <kbd>Ctrl</kbd>.
