# Axon

*Axon was developed by Herbert Sauro in collaboration with [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant.*

Axon is a programming language for scientific computing. Matrices, complex numbers and calls into native numerical libraries are part of the language rather than add-ons. The syntax borrows what scientists already read fluently (MATLAB-style matrix literals, 1-based indexing, `end`-delimited blocks) and adds a module system, records, keyword arguments and optional type annotations.

This repository holds the interpreter, written in Delphi, its standard library, and the Axon IDE.

```axon
import ode

# Linear algebra is built in: \ solves A x = b.
A = [4.0, 1.0; 1.0, 3.0]
b = [1.0; 2.0]
println(A \ b)

# Lotka-Volterra predator and prey, solved with RK45.
p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}
f = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2]; p.c*y[1]*y[2] - p.d*y[2]]
end
sol = ode.solve(f, [10.0; 5.0], [0, 50])
println("steps:", sol.nsteps, "prey at t = 50:", format(sol.y[1, end], 2))
```

## Features

- **Numbers and arrays.** `int`, `real` and `complex` scalars; dense vectors and matrices with broadcasting, BLAS products and LAPACK-backed `\`, `/` and `^`; sparse matrices with a built-in sparse LU.
- **Language.** Functions with keyword arguments, closures, records, lists and dictionaries, `try`/`catch`, optional type annotations, and modules with explicit exports.
- **Standard library.** `linalg` (solve, eig, svd, qr, lu, chol, expm, ...), `ode` (RK45 and stiff BDF through SUNDIALS CVODE, with events and dense output), `plot` (line, scatter, bar, histogram and surface plots to PNG, SVG or PDF), `random`, `time` and `io`.
- **Speed.** A JIT compiler built on [MIR](https://github.com/vnmakarov/mir) compiles numeric functions to native code at their first call, often hundreds of times faster than interpreting them, with identical results. ODE stepping loops run natively.
- **Native code.** `extern` blocks call C libraries directly, including callbacks.
- **IDE.** An editor with syntax colouring and as-you-type checks, a REPL that can run whole files and keep their variables, a plot pane with an interactive chart (zoom, pan, editing) for line, scatter, bar and histogram plots, F1 help that shows the matching section of the Language Reference, a searchable documentation viewer, and light and dark themes.

## Platforms

- **Windows (x64):** the interpreter, the IDE and all native libraries.
- **macOS (Apple Silicon):** the IDE, with the interpreter inside its app bundle, deployed through RAD Studio's PAServer, with OpenBLAS, CVODE and the JIT.

## Building

Axon is built with Embarcadero RAD Studio 13 (Delphi, BDS 37.0).

- **In RAD Studio:** open `Axon.groupproj` and use **Build All**. It builds the interpreter (`axon.dproj`), whose post-build step copies the native libraries, `stdlib`, examples and help into `Win64\<Config>`, then the IDE (`ide\AxonIDE.dproj`) into the same folder.
- **From the command line:** `build.cmd` builds Win64 Debug, and `build.cmd Release` builds Release.
- **Tests:** `test.cmd` runs the test suite; `test.cmd -jit` runs it with the JIT off, on and forced.

The IDE uses three components of mine that live in their own repositories: the [RhoSkiaCodeEditor](https://github.com/hsauro/RhoSkiaCodeEditor) code editor, the [RhoMarkdownViewer](https://github.com/hsauro/RhoMarkdownViewer) markdown viewer, and the [Plot2DComponent](https://github.com/hsauro/Plot2DComponent) interactive chart. The IDE project finds their source through its unit search path, in a `RhodyComponents` folder next to the Axon folder, so clone them there under these names:

```
cd ..
git clone https://github.com/hsauro/RhoSkiaCodeEditor.git RhodyComponents/RhoEditor
git clone https://github.com/hsauro/RhoMarkdownViewer.git RhodyComponents/RhoMarkDownViewer
git clone https://github.com/hsauro/Plot2DComponent.git RhodyComponents/PlottingComponent
```

The interpreter (`axon.dproj`) needs neither.

Prebuilt native libraries are in `lib/win64` and `lib/macos`; see [lib/README.md](lib/README.md) for where each came from and how to rebuild it. The macOS libraries are built on the Mac by scripts in `tools/`.

## Running

- `axon file.sci` runs a program; `axon` on its own starts the REPL, where `help name` shows documentation.
- `AxonIDE` opens the IDE. Its Welcome tab lists the examples in [examples/](examples), from basics to ODEs, linear algebra, sparse matrices, random numbers and plots.

## Documentation

- [Language Reference](doc/Axon-Language-Reference.md): the exact syntax and semantics.
- [White Paper](doc/Axon-White-Paper.md): the design rationale, with examples.
- [help/](help): the IDE's help pages, including getting started and a tour of the language.

## Licence

Axon's own code and documentation are released under the [MIT licence](LICENSE). The prebuilt native libraries in `lib/` are third-party software under their own licences, listed in [lib/README.md](lib/README.md): OpenBLAS, SUNDIALS, Skia and MIR are BSD or MIT licensed, and the MinGW runtime DLLs are GPL with the GCC Runtime Library Exception.
