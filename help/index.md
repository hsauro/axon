# Axon documentation

Axon is a language for scientific computing: matrices, complex numbers, ODE
solvers and plots, with a small core and readable code.

## Start here

- [Getting started](getting-started.md): run your first program, use the REPL, find help.
- [Using the IDE](ide.md): running, the output and REPL panes, plots, help and shortcuts.
- [A tour of Axon](tour.md): the language in one page, with examples you can run.

## Reference

The [Language Reference](Axon-Language-Reference.md) is the complete, exact
description of Axon. Some sections you may want often:

| Topic | Section |
| --- | --- |
| How values are displayed | [Display](Axon-Language-Reference.md#display) |
| Printing: `print` and `println` | [Printing](Axon-Language-Reference.md#printing) |
| Matrix product, solving `A \ b`, powers, broadcasting | [Linear-algebra operators](Axon-Language-Reference.md#linear-algebra-operators) |
| Indexing and ranges | [Indexing and ranges](Axon-Language-Reference.md#indexing-and-ranges) |
| Scopes and closures | [Scopes](Axon-Language-Reference.md#scopes) |
| Errors and their kinds | [Errors](Axon-Language-Reference.md#errors) |
| Sparse matrices | [Sparse operands](Axon-Language-Reference.md#sparse-operands) |
| `linalg`: solve, eig, svd, ... | [The linalg module](Axon-Language-Reference.md#the-linalg-module) |
| `ode`: differential equations | [The ode module](Axon-Language-Reference.md#the-ode-module) |
| `plot`: line, scatter, histogram, surface | [The plot module](Axon-Language-Reference.md#the-plot-module) |
| `random`: uniform, normal and integer random numbers | [The random module](Axon-Language-Reference.md#the-random-module) |
| `time`: clocks and timing code | [The time module](Axon-Language-Reference.md#the-time-module) |
| `graphics`: drawing to PNG, SVG, PDF | [The graphics module](Axon-Language-Reference.md#the-graphics-module) |
| `io`: reading and writing files | [The io module](Axon-Language-Reference.md#the-io-module) |
| Modules and packages | [Modules](Axon-Language-Reference.md#modules) |
| Calling C libraries | [Foreign functions](Axon-Language-Reference.md#foreign-functions) |
| The REPL and `help` | [The REPL](Axon-Language-Reference.md#the-repl) |

The [White Paper](Axon-White-Paper.md) explains why Axon is designed the way it
is, with longer examples.

## Examples

Each example opens as your own copy, so you can change it and run it with
<kbd>F9</kbd>.

- [Basics: values, functions, loops and printing](../examples/01_basics.sci)
- [Collections: lists, records and dictionaries](../examples/02_collections.sci)
- [Linear algebra](../examples/03_linear_algebra.sci)
- [Lotka-Volterra predator and prey](../examples/04_lotka_volterra.sci)
- [Stiff equations and events](../examples/05_stiff_and_events.sci)
- [Sparse matrices](../examples/06_sparse.sci)
- [A surface plot](../examples/07_surface.sci)
