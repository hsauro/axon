# Using the IDE

[Contents](index.md)

## The window

| Area | What it shows |
| --- | --- |
| Editor tabs | Your files, with syntax colouring and line numbers. The **Welcome** tab lists recent files and the examples. |
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

## Compiled and interpreted

Functions are compiled to native code at their first call, which makes
loops and recursive functions hundreds of times faster. The **JIT** button
in the toolbar (or **Run > Use JIT Compiler**) switches this off and on, so
you can run the same program both ways and compare: the results are the
same, only the time differs. The *JIT: compiled and interpreted* example
on the welcome screen is made for this.

After a run with the JIT on, the Output pane lists the functions that were
compiled, and for those that ran interpreted, the reason, such as a
parameter without a type annotation. The REPL follows the setting when it
starts: use **Run > Restart REPL** after switching.

## The REPL pane

Type a statement and press <kbd>Enter</kbd>. A session starts the first time
you use it, in the current file's folder, and keeps its variables until you
press **Restart**, which also stops a statement that does not finish. **Clear**
empties the transcript.

## Plots

`plot.show()` displays the current figure in the plot pane at once, even while
the program is still running. Figures saved with `plot.save("name.png")` are
shown too, when the program ends.

## Help

<kbd>F1</kbd> shows help on the name under the caret: a built-in function, a
function from an imported module (`ode.solve`, or `solve` after
`from linalg import solve`), or a function or record defined in the file with a
`##` comment above it.

## Shortcuts

| Key | Action |
| --- | --- |
| <kbd>F9</kbd> | Run the current file |
| <kbd>Ctrl+F2</kbd> | Stop the running program |
| <kbd>Ctrl+Enter</kbd> | Send the current line or selection to the REPL |
| <kbd>F1</kbd> | Help on the word under the caret |
| <kbd>Ctrl+N</kbd>, <kbd>Ctrl+O</kbd>, <kbd>Ctrl+S</kbd> | New, open, save |
| <kbd>Shift+Ctrl+S</kbd> | Save as |
| <kbd>Ctrl+W</kbd> | Close the current tab |
| <kbd>Ctrl+F</kbd> | Find and replace |
| <kbd>Ctrl+G</kbd> | Go to line |
| <kbd>Ctrl+/</kbd> | Comment or uncomment the selected lines |
| <kbd>Ctrl+Z</kbd>, <kbd>Ctrl+Y</kbd> | Undo, redo |

On macOS, use <kbd>Cmd</kbd> in place of <kbd>Ctrl</kbd>.
