# Axon Milestones

Nov 7, 2026 · Herbert Sauro

Axon is built in 14 milestones, M0 to M13, followed by two later stages. Each milestone has a fixed scope and a set of acceptance tests. A milestone is done when its own tests and every earlier milestone's tests pass on Windows and macOS. Linux is deferred.

The project's three design documents live in the repository's `doc/` folder: [Axon White Paper](Axon-White-Paper.md), [Axon Language Reference](Axon-Language-Reference.md) and this plan, [Axon Milestones](Axon-Milestones.md). The reference is the authority on behaviour; where this plan and the reference disagree, the reference wins.

## How the tests work

Tests live in `tests/mNN/`, one folder per milestone. Every test is an Axon source file run by the interpreter, and there are three kinds:

- **Output tests.** `name.sci` runs to completion and its standard output must match `name.out` exactly.
- **Error tests.** The first line is `#! error: Kind`, for example `#! error: IndexError`. The program must stop with an uncaught error of that kind. The message is not compared unless the test also has a `name.err` file, which must then match standard error exactly; this is how error locations and the report format are tested.
- **Front-end tests.** For M1 and M2, `axon --tokens name.sci` and `axon --ast name.sci` print the token stream or the syntax tree, compared against `name.tokens` or `name.ast`.

The command `axon test tests/` runs every test and reports passes and failures by milestone. Each milestone below lists the behaviours its tests must cover, and every rule in the reference should be covered by at least one test by the end of M13.

## Front end

### M0 — Project skeleton

This milestone sets up the repository, the build and the test runner before any language work starts. The interpreter is written in Object Pascal with Delphi.

- [ ] Delphi project builds an `axon` console executable for Win64 and macOS (arm64 and x64); Linux is deferred
- [x] Builds run from the command line (MSBuild or `dcc`), so CI and Claude Code can build without the IDE
- [ ] C libraries (libffi, BLAS/LAPACK, UMFPACK or KLU, CVODE, and later MIR) bound through Delphi `external` declarations in one unit per library; libffi provides the closures for `callback`
- [x] Platform-specific code kept behind `{$IFDEF}` in a few units, so a Linux target can be added later without restructuring
- [x] `axon test tests/` runs the three test kinds and reports results by milestone
- [x] Local `build` and `test` scripts for Win64, runnable by you or Claude Code on the Windows machine
- [ ] macOS builds made through PAServer from the same machine; the macOS test run is a manual check before each milestone is closed
- [x] Hosted CI is deferred; a self-hosted Windows runner can be added later

### M1 — Lexer

The lexer turns source text into tokens following the [Lexical structure](Axon-Language-Reference.md#lexical-structure) section of the reference.

- [x] Identifiers, keywords and the `extern`-only contextual keywords
- [x] Integer, real and imaginary literals, including `_` separators, exponents, and rejection of `.5` and `1.`
- [x] `2i` as an imaginary literal, but `i` alone and `2in` as other tokens
- [x] Strings with all escapes
- [x] `#` comments, nested `#= … =#` block comments, and `##` docstrings kept as tokens
- [x] A `NEWLINE` token at every line end, with no bracket tracking in the lexer (newline handling is the parser's job in M2)
- [x] Every operator, with `.*` and `1.0+x` lexed correctly
- [x] Errors report file, line and column

### M2 — Parser

The parser builds the syntax tree for the full grammar, and `axon --ast` prints it.

- [x] Every statement and expression form in the grammar
- [x] Newline handling: skipped inside brackets and after a binary operator or comma, restored inside every block body, including an anonymous function passed as an argument
- [x] No terminator needed before `end`, `elseif`, `else` and `catch`
- [x] Typed assignment `x: real = 0.0` told apart from the expression `x:n` by backtracking
- [x] `{a:b}` parsed as a record and `{(a:b)}` as a list
- [x] All ten precedence levels, with every worked case from the reference's [Operator precedence](Axon-Language-Reference.md#operator-precedence) section parsing as shown
- [x] Chained comparisons and chained ranges rejected
- [x] Destructuring `[a, b] = …` told apart from a matrix literal
- [x] List and record brace literals told apart, with `{}` as the empty list
- [x] Keyword arguments, `=>` pairs, and `end` inside index brackets
- [x] Syntax errors report the location and what was expected

## Core evaluation

### M3 — Scalar evaluator

A tree-walking evaluator runs scripts that use scalars, strings and control flow. `print` and raising errors with a kind exist from this milestone onward, because later tests depend on them.

- [x] `bool`, `int`, `real`, `complex` and `string` values, and `nothing`
- [x] Arithmetic with promotion along `bool` → `int` → `real` → `complex`; `int / int` gives a `real`; `div` and `mod`
- [x] `OverflowError` on 64-bit integer overflow, and NaN for `sqrt(-1.0)` and `log(-1.0)`
- [x] Elementary functions on scalars, with principal values for complex arguments
- [x] Comparisons, with NaN behaviour and `TypeError` for ordering complex numbers
- [x] `and`, `or` and `not` with short-circuiting, verified by a side effect in the right operand
- [x] `if`, `while`, `for` over ranges (including real steps and `0:0.1:1` having 11 elements), `break` and `continue`
- [x] Conditions must be scalar `bool`, else `TypeError`
- [x] String `+`, `string(x)`, `print`, and every display form in the reference's [Display](Axon-Language-Reference.md#display) table
- [x] `NameError` for an unbound name

### M4 — Functions and scoping

This milestone adds named functions, anonymous functions and the full scoping rules.

- [ ] Named and anonymous functions, recursion, and calls before the definition within a file
- [ ] Keyword parameters with defaults evaluated at each call; every `ArgumentError` case in the reference
- [ ] Multiple returns and destructuring, with count mismatch as an error
- [ ] Value semantics for every argument, and `nothing` returned when there is no `return` value
- [ ] Scope rules 1 to 7, each with its own test, including the `if`-body assignment that stays visible after `end`
- [ ] Closures capturing by reference, the `count`/`tick` example giving 2, and the `local` version giving 0
- [ ] Top-level functions needing `global` to assign module variables
- [ ] Type annotations on parameters, returns and variables checked at run time

### M5 — Errors

This milestone completes error handling.

- [ ] `try … catch err … end`, catching errors raised in called functions
- [ ] The `err` record's `kind`, `message` and `trace` fields
- [ ] `error("text")`, `error(kind, "text")` and re-raising with `error(err)`
- [ ] At least one error test for every kind in the reference's [error table](Axon-Language-Reference.md#errors) that is reachable so far
- [ ] The uncaught-error report format

## Data

### M6 — Dense matrices

This milestone adds vectors and matrices in pure code, without BLAS. The matrix product is a simple triple loop, to be replaced in M10.

- [ ] Matrix literals and block concatenation, with `DimensionError` for ragged rows
- [ ] `[1; 2; 3]` as a vector, `[1, 2, 3]` as a 1×3 matrix and `[]` as 0×0, with element type taken from the widest entry
- [ ] Constructors: `zeros`, `ones`, `eye`, `linspace`, `rand`, `size`, `length`
- [ ] `+`, `-` and the four dot operators with broadcasting, including `A - mean(A, 1)`
- [ ] `*` as the matrix product, including matrix times vector and `v' * w` as a scalar
- [ ] `A'` as the plain transpose, `adjoint`, `dot`, and elementary functions applied elementwise
- [ ] Elementwise comparisons, `isequal`, and `and`/`or`/`not` on `bool` arrays
- [ ] Every index form, linear indexing, result shapes, and `end` binding to the innermost indexed object
- [ ] `IndexError` out of bounds, with no growth on assignment
- [ ] Indexed assignment with scalar broadcast, shape checks, and element-type widening
- [ ] Copy-on-write: `B = A` then writing to `B` leaves `A` unchanged, and a read-only function call makes no copy (checked with a test hook that counts copies)
- [ ] Aligned matrix display, with large matrices elided

### M7 — Collections

This milestone adds lists, records and dictionaries.

- [ ] List literals, indexing, range slices, iteration with `for`, and `append`
- [ ] Record literals with field access, and assignment that adds fields
- [ ] Declared `record` types with `FieldError` and field type checks
- [ ] `dict` with `=>` pairs, `KeyError`, and `get` with a default
- [ ] Value semantics for all three, including nested values
- [ ] A list of records used as a metadata table, matching the [white paper's example](Axon-White-Paper.md#collections-lists-records-and-dictionaries)

## Modules, native code and numerics

### M8 — Modules and packages

This milestone adds multi-file programs.

- [ ] `import m`, `import m as x`, `from m import a, b`, and dotted names for directories
- [ ] Only `export`ed names are visible, and imported names are read-only
- [ ] The search order: the importing file's directory, then `package.toml` packages, then the standard library
- [ ] Each module loads once, functions are bound before top-level statements run, and a cycle raises `ImportError` naming the chain
- [ ] `package.toml` parsing, including `[native.*]` entries per platform
- [ ] Tests use a fixture tree of small modules and packages under `tests/m08/`

### M9 — Foreign function interface

This milestone adds `extern`, built on libffi. Tests use a small C test library built alongside the interpreter.

- [ ] Library resolution through `package.toml` and then the system path; `ForeignError` for a missing library or symbol
- [ ] By-value scalars, with `TypeError` for values that do not fit the C type
- [ ] `ref T` writing back into the argument variable
- [ ] `ptr T` passing a matrix buffer with no copy, made unique first when it is shared
- [ ] `cstring` and `name "..."` symbol binding
- [ ] `callback` trampolines, `keep(cb)`, and an error raised inside a callback re-raised after the native call returns
- [ ] A callback invoked from another thread raises `ForeignError`

### M10 — Linear algebra

This milestone adds the `linalg` module, written in Axon over BLAS and LAPACK through `extern`, and switches `*` to BLAS.

- [ ] `*` uses `dgemm`/`zgemm`, with results matching M6's tests
- [ ] `\`, `/`, `solve` and `lstsq`, with `SingularMatrix` for a singular system
- [ ] `det`, `inv`, `eig`, `svd`, `qr`, `lu`, `chol`, `rank`, `null`, `norm` and `expm`, for real and complex input
- [ ] Matrix powers `A ^ k`
- [ ] Results checked against reference values to a stated tolerance, with a tolerance-aware comparison helper in the test library

### M11 — Sparse matrices

This milestone adds the core sparse type and its solvers.

- [ ] `sparse(i, j, v, m, n)`, `speye`, `nnz` and `full`, stored as CSC
- [ ] Arithmetic stays sparse where the reference says so and becomes dense otherwise
- [ ] Indexing and indexed assignment on sparse matrices
- [ ] `S \ b` and sparse `lu` through UMFPACK or KLU
- [ ] Sparse display in the REPL

## Tooling and packages

### M12 — REPL and documentation

This milestone finishes the interactive environment. A basic REPL exists from M3; here it reaches the white paper's standard.

- [ ] Multi-line input that waits for an open block or bracket to close
- [ ] A trailing `;` suppresses display
- [ ] Display of every type, matching the white paper's examples
- [ ] An uncaught error returns to the prompt with variables intact
- [ ] `help name` shows the `##` docstring of a function, record or module
- [ ] REPL behaviour tested by feeding scripted input and comparing a transcript

### M13 — Official packages

This milestone ships `ode` and `plot` as packages written in Axon. It is the first full end-to-end test of the language.

- [ ] `ode.solve` with RK45 (written in Axon) and BDF (CVODE through `extern` with a callback), events, dense output, and a result record with `t`, `y`, `names` and `status`
- [ ] `plot.line`, `plot.scatter` and `plot.surface`, with styling through keyword arguments, writing PNG and SVG files
- [ ] The white paper's Lotka–Volterra [worked example](Axon-White-Paper.md#worked-example) runs unchanged, and the eigenvalues of its Jacobian form a purely imaginary pair
- [ ] ODE results checked against analytic solutions, such as exponential decay and the harmonic oscillator

## Later stages

These stages start after M13 and are planned in outline only. Each gets its own detailed milestone list when it begins.

### L1 — Automatic differentiation

- [ ] Forward-mode `ad` module with `grad`, `jacobian` and `derivative`, using dual numbers
- [ ] Differentiation through closures, loops and complex arithmetic
- [ ] `ad.rule` for `extern` functions, with rules shipped for `solve`, `inv`, `det` and `eig`
- [ ] AD derivatives checked against analytic derivatives and finite differences
- [ ] Exact Jacobians passed to the `ode` BDF solver

### L2 — MIR JIT

- [ ] A bytecode VM replaces the tree-walker, passing all M0–M13 tests unchanged
- [ ] Annotated, type-stable functions translated to MIR and compiled in-process
- [ ] Fallback to the interpreter for anything the JIT cannot compile
- [ ] Compiled ODE right-hand sides passed to CVODE as native callbacks
- [ ] The full test suite passes with the JIT forced on, plus benchmarks showing the speed-up on scalar loops
