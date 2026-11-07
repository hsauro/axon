# Axon White Paper

Nov 7, 2026 · Herbert Sauro

## Abstract

This paper proposes Axon, a standalone programming language for scientific computing in which matrices, complex numbers and calls into native numerical libraries are part of the language rather than add-ons. The syntax borrows what scientists already read fluently (MATLAB-style matrix literals, 1-based indexing, `end`-delimited blocks) and adds what MATLAB lacks: a real module system, records, keyword arguments, optional type annotations and a declarative foreign function interface.

The target user writes models, solvers and analysis scripts, and wants code that reads like the mathematics in a textbook. Axon source files use the `.sci` extension, and `.txt` files are also accepted as source.

The exact syntax and semantics are defined in the [Axon Language Reference](Axon-Language-Reference.md), and the build plan is in [Axon Milestones](Axon-Milestones.md).

## Design principles

1. **Read like the mathematics.** Notation should match the textbook: `A*x`, `A \ b`, `A'`, `v[end]`.
2. **Matrices and complex numbers are first-class.** They are built into the literal syntax and the numeric tower, not library objects.
3. **Type-stable by default.** A function's output type follows from its input types. Real code never silently becomes complex.
4. **Native libraries are a declaration away.** BLAS, LAPACK and solvers such as CVODE are called through in-language `extern` declarations, without wrapper generators.
5. **Small core, versioned packages.** Linear algebra, elementary functions and complex arithmetic are core. ODE solvers and plotting are official packages.
6. **Explicit over implicit at module boundaries.** Exports are declared and imports are qualified, with no wildcards.

## Lexical structure and statements

Statements end at a newline and blocks close with `end`. Whitespace carries no meaning, and `;` is free for matrix row separation.

```
function rk4_step(f, t, y, h)
  k1 = f(t, y)
  k2 = f(t + h/2, y + h/2*k1)
  k3 = f(t + h/2, y + h/2*k2)
  k4 = f(t + h, y + h*k3)
  return y + h/6*(k1 + 2*k2 + 2*k3 + k4)
end
```

- **Continuation.** A line continues if it ends inside an open bracket or with a binary operator.
- **Output suppression.** In the REPL a trailing `;` suppresses display. It parses as an empty statement, so it doesn't conflict with newline termination.
- **Comments.** `#` starts a line comment, `#=` … `=#` delimits a block comment, which may span lines and nests so code containing comments can be commented out, and `##` starts a docstring line (see REPL and documentation).
- **Strings.** Strings use double quotes only, which leaves `'` unambiguous as the transpose operator.
- **Control flow.** `if … elseif … else … end`, `for i in 1:n … end`, `while … end`, `break` and `continue`.

## Numeric types, complex numbers and matrices

The numeric tower is `int` → `real` → `complex`, with fixed-width variants (`int32`, `float32`, `float64`) used mainly at the FFI boundary. Mixed arithmetic promotes upward; nothing demotes implicitly.

### Complex numbers

The imaginary unit is a literal suffix, which leaves `i` and `j` free as loop variables:

```
z = 3 + 4i
w = 2.5e-3i
abs(z)        # 5.0
conj(z)       # 3.0 - 4.0i
```

Functions are type-stable. `sqrt(-1.0)` returns NaN, whereas `sqrt(-1.0 + 0i)` returns `1i`. Silent promotion to complex, as MATLAB does, hides bugs in code meant to be real-valued.

### Matrices and vectors

Matrix literals follow MATLAB: `,` separates columns and `;` separates rows.

```
A = [1, 2; 3, 4]      # 2×2 matrix
r = [1, 2, 3]         # row vector
c = [1; 2; 3]         # column vector
B = [A, A; A, A]      # block concatenation
```

- **Vectors versus n×1 matrices.** The type system distinguishes a vector from an n×1 matrix, but the literal syntax doesn't make the user think about it. `A*v` with a vector `v` returns a vector.
- **Storage.** Storage is column-major, so passing a matrix to BLAS or LAPACK is zero-copy.
- **Element types.** The element type is inferred from the literal. Any complex entry makes the whole matrix complex.
- **Constructors.** `zeros(m, n)`, `ones`, `eye`, `rand`, `linspace(a, b, n)` and `a:h:b`.

### Assignment copies

Assigning a matrix copies it. After `B = A`, changing `B[1, 1]` leaves `A` unchanged, and a function that modifies a matrix argument modifies its own copy. This is less surprising to new users than aliasing.

Internally the copy is deferred (copy-on-write): `B = A` shares storage until one of them is written, so passing large matrices to read-only functions costs nothing.

### Sparse matrices

Sparse matrices are a core type, stored in compressed sparse column (CSC) form.

```
S = sparse(i, j, v, m, n)     # from triplets
I = speye(1000)
nnz(S)                        # stored non-zeros
x = S \ b                     # sparse direct solve
F = full(S)                   # convert to dense
```

Operators work unchanged on sparse operands. A result stays sparse where sparsity is guaranteed (`S + S`, `S * S`, `2*S`, `S'`) and becomes dense otherwise (`S + A` with dense `A`). Sparse solves call a native direct solver such as UMFPACK or KLU through `extern`.

## Collections: lists, records and dictionaries

Matrices hold numbers and booleans only. Other data, such as names, labels and per-item metadata, lives in three general containers.

| Container | Literal | Use |
| --- | --- | --- |
| List | `{1, "S1", A}` | Ordered, heterogeneous, 1-based; `{}` is the empty list |
| Record | `{name: "S1", init: 10.0}` | Fixed named fields, accessed with `.` (see Records below) |
| Dictionary | `dict("Km" => 0.5, "Vm" => 10.0)` | Keys added at run time, accessed with `d["Km"]` |

The parser tells a list literal from a record literal by whether the first element has the form `name:`.

A table of metadata is a list of records, and it indexes and iterates like any other list:

```
species = {
  {name: "S1", init: 10.0, units: "mM"},
  {name: "S2", init: 0.0,  units: "mM"}
}

species[2].name           # "S2"
for s in species
  print(s.name, s.init)
end
```

A function that returns numbers together with their metadata returns a record that holds both. For example, an ODE result has `sol.y` as a matrix and `sol.names` as a list of strings, and `sol.y[k, :]` is the trajectory of `sol.names[k]`.

## Operators and indexing

Arithmetic operators default to linear algebra; elementwise forms carry a leading dot.

| Operator | Meaning |
| --- | --- |
| `A * B` | Matrix product: each entry is a row of `A` dotted with a column of `B` (scalar product when either operand is a scalar) |
| `A .* B`, `A ./ B`, `A .\ B`, `A .^ p` | Elementwise multiply, divide, left divide, power |
| `A + B`, `A - B` | Elementwise sum and difference, with broadcasting |
| `A \ b` | Solve `A x = b` (least squares when `A` is not square) |
| `A / B` | Right division, `A * inv(B)` |
| `A ^ k` | Matrix power |
| `A'` | Plain transpose; `adjoint(A)` gives the conjugate transpose |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | Comparison; elementwise on arrays, with `isequal(A, B)` for whole-value equality |
| `and`, `or`, `not` | Logic; short-circuit on scalars, elementwise on `bool` arrays |

Only four operators carry a dot, and each is the element-by-element form of an operator whose plain form means the matrix operation. Elementwise operations broadcast singleton dimensions, so `A - mean(A, 1)` subtracts each column's mean. Keeping punctuation to this minimum keeps code readable for novices.

### Indexing

Indexing is 1-based with inclusive ranges, and uses square brackets so indexing and function calls never look alike.

```
A[2, 3]               # element
A[2, :]               # row 2
A[1:end-1, 3]         # column 3 without its last element
v[end]                # last element
A[A > 0 and A < 5]    # logical mask
A[:, [1, 3]]          # columns 1 and 3
```

`end` inside an index refers to the length of that dimension. Out-of-bounds access is an error and never grows the array; growth goes through `append` or explicit concatenation.

## Functions, closures and records

### Functions

```
function norm2(v)
  return sqrt(sum(abs(v).^2))
end

sq = function(x) return x^2 end      # anonymous function
```

Functions are first-class values. Anonymous functions capture variables from the enclosing scope by reference, so a model's right-hand side can close over its parameters:

```
A = [-1, 0.5; 0.2, -0.8]
f = function(t, y) return A*y end
```

A closure sees the variable itself, not a snapshot. It can also assign to a captured variable, with no extra keyword:

```
count = 0
tick = function() count = count + 1 end
tick(); tick()
count              # 2
```

### Scoping

- **Parameters** are always local.
- **`local x`** always creates a new variable in the current function or block, shadowing any outer `x`.
- **Plain assignment `x = …`** refers to an existing variable in an enclosing scope if there is one, and otherwise creates a local.
- **Named top-level functions** cannot assign to script or module variables unless they declare `global x`. Closures and nested functions see their enclosing scope, but a library function never silently overwrites a user's variable.

For example, `local` keeps a closure's counter separate from the outer one:

```
count = 0
tick = function()
  local count = 0
  count = count + 1
end
tick(); tick()
count              # still 0
```

### Keyword arguments

Parameters after a `;` in the signature are keyword-only and may have defaults:

```
function solve(f, y0, tspan; method="bdf", rtol=1e-6, atol=1e-9)
  ...
end

sol = solve(f, y0, [0, 10], rtol=1e-8)
```

The solver and plotting APIs depend on this feature. Without keywords they degrade into long positional argument lists.

### Multiple returns

A function returns several values with `return U, S, V`. The caller unpacks them with matrix-literal brackets on the left-hand side, `[U, S, V] = svd(A)`, and no tuple type is exposed to the user.

### Records

A record literal gives a named, lightweight structure for parameter sets and results:

```
p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}
p.a              # 1.0
```

A typed record declaration is optional and adds checking:

```
record LVParams
  a: real; b: real; c: real; d: real
end
```

Library functions return records, such as `sol.t`, `sol.y` and `sol.status` from an ODE solve.

### Errors

Errors are raised with `error("message")` and handled with `try … catch … end`:

```
try
  x = A \ b
catch err
  print("solve failed: ", err.message)
  x = linalg.lstsq(A, b)
end
```

`err` is a record with fields `message`, `kind` (for example `"SingularMatrix"` or `"IndexError"`) and `trace`. Library code raises errors with a specific `kind`, so callers can test `err.kind` and re-raise errors they do not handle with `error(err)`.

## Argument passing

Every argument is passed with value semantics, whatever its type: scalars, strings, matrices, sparse matrices, lists, records and dictionaries alike. A function that modifies an argument modifies its own copy, and the caller's variable is unchanged.

```
function zero_corner(A)
  A[1, 1] = 0
  return A
end

M = [1, 2; 3, 4]
N = zero_corner(M)
M[1, 1]            # still 1
N[1, 1]            # 0
```

- **Cost.** Arguments are shared under copy-on-write, so a copy is made only if the function writes to the argument. Passing a large matrix to a function that only reads it costs nothing.
- **Results come back through `return`.** There are no `var` or out parameters. A function with several results uses multiple returns, as in `[L, U] = lu(A)`, so everything a call changes is visible on the left-hand side.
- **Closures are separate.** A closure captures outer variables by reference (see Scoping). That is capture, not argument passing, and the two rules do not interact.
- **`extern` calls.** `ref T` and `ptr T` describe the C calling convention, not language semantics. For a `ref` argument the runtime copies the native result back into the variable after the call, and a `ptr` argument passes the variable's own buffer with no copy. If that buffer is shared under copy-on-write, it is made unique first, so native code writes only to that one variable.

In-place updates of a caller's matrix, for example a solver workspace reused across calls, are deliberately not supported in the first version. If profiling shows they are needed, they will be added as an explicit form that is visible at the call site.

## Types and annotations

The language is dynamically typed, with optional annotations in Pascal form:

```
function norm2(v: vector): real
  ...
end

x: real = 0.0
```

Annotations serve three purposes:

- **Runtime checks at call boundaries.** A mismatch raises an error that names the argument.
- **Required types at the FFI boundary.** Every `extern` parameter is annotated, because the C signature needs exact widths.
- **Hints for a later compiler.** Annotated, type-stable functions can be compiled to native code without changing the language.

Code without annotations still runs, so scripts and REPL work carry no overhead.

### Data types

| Type | Literal or constructor | Description |
| --- | --- | --- |
| `bool` | `true`, `false` | Logical value |
| `int` | `42`, `-7` | 64-bit signed integer |
| `real` | `3.14`, `1e-6` | 64-bit IEEE double |
| `complex` | `3 + 4i`, `2.5e-3i` | Pair of 64-bit doubles, C99 `double _Complex` layout |
| `string` | `"S1"` | Immutable UTF-8 text |
| `range` | `1:n`, `0:0.1:1` | Lazy arithmetic sequence, inclusive at both ends |
| `vector{T}` | `[1; 2; 3]`, `linspace(0, 1, 5)` | One-dimensional dense array; `T` is `bool`, `int`, `real` or `complex` |
| `matrix{T}` | `[1, 2; 3, 4]`, `zeros(m, n)` | Two-dimensional dense array, column-major |
| `sparse{T}` | `sparse(i, j, v, m, n)`, `speye(n)` | Sparse matrix in compressed sparse column form |
| `list` | `{1, "S1", A}` | Ordered, heterogeneous collection |
| `record` | `{name: "S1", init: 10.0}` | Named fields; typed form via `record … end` |
| `dict` | `dict("Km" => 0.5)` | Key–value map; keys are strings or numbers |
| `function` | `function(x) return x^2 end` | First-class function or closure |
| `nothing` | `nothing` | The value of a function with no `return` value |

Types used only in `extern` declarations are the fixed-width numerics `int8` … `int64`, `uint8` … `uint64`, `float32` and `float64`, the platform-sized `clong` (C `long`) and `csize` (C `size_t`), plus `char`, `cstring`, `ref T`, `ptr T` and `callback(…)`.

Parameterised forms such as `matrix{complex}` constrain the element type in an annotation, and plain `matrix` accepts any element type. Mixed arithmetic promotes along `bool` → `int` → `real` → `complex` and never demotes implicitly.

## Modules, imports and packages

Each file is a module named after the file, so there is no module header to keep in sync. Top-level statements run when the file is executed directly, which makes scripts work without ceremony.

```
# odes.sci
export function lotka(t, y, p)
  return [p.a*y[1] - p.b*y[1]*y[2];  p.c*y[1]*y[2] - p.d*y[2]]
end
```

Only names marked `export` are visible to importers. This gives every library a stable public surface.

### Imports

```
import linalg               # linalg.eig(A)
import linalg as la         # la.eig(A)
from linalg import eig, svd
```

There is no wildcard import. A directory of modules is imported with dotted names, as in `import ode.stiff`.

### Packages

A directory containing `package.toml` is a package. The manifest records the name, version, dependencies, and the native libraries the package binds to on each platform:

```
[package]
name = "ode"
version = "0.3.0"

[native.cvode]
linux   = "libsundials_cvode.so"
macos   = "libsundials_cvode.dylib"
windows = "sundials_cvode.dll"
```

Source code refers to `extern "cvode"` by its logical name and the manifest resolves the path, so scripts stay portable without platform conditionals.

## Foreign function interface

Native functions are declared inside the language with C-ABI signatures, in the spirit of Delphi's `external`. No wrapper generator or compiled glue code is needed.

```
extern "openblas"
  function ddot_(n: ref int32, x: ptr float64, incx: ref int32,
                 y: ptr float64, incy: ref int32): float64
  function dgesv_(n: ref int32, nrhs: ref int32, a: ptr float64, lda: ref int32,
                  ipiv: ptr int32, b: ptr float64, ldb: ref int32,
                  info: ref int32)
end
```

### Parameter modes

- **Plain types** such as `int32` and `float64` are passed by value.
- **`ref T`** passes a pointer to a single value. The callee may write through it, and the caller sees the result in the variable.
- **`ptr T`** passes a pointer to contiguous data. Passing a `matrix{float64}` or `vector{complex}` hands over its buffer with no copy, because storage is column-major and `complex` matches C99 `double _Complex` layout.
- **`cstring`** converts to a null-terminated UTF-8 string for the duration of the call.
- **`name "..."`** after a declaration binds a different symbol name, for example to drop Fortran's trailing underscores.

### Callbacks

Solvers such as CVODE call back into user code, so a language function must be passable as a C function pointer. The `callback` type declares the expected signature:

```
extern "cvode"
  type RhsFn = callback(t: float64, y: ptr float64, ydot: ptr float64,
                        user: ptr void): int32
  function CVodeInit(mem: ptr void, f: RhsFn, t0: float64, y0: ptr void): int32
end
```

When a language function is passed where a `callback` is expected, the runtime generates a trampoline that converts arguments, calls the function, and returns its result. The trampoline is kept alive as long as the native side holds it. An error raised inside a callback is caught at the trampoline, reported back as the declared error return, and re-raised in the language once the native call returns.

### Idiomatic wrappers

Raw `extern` declarations stay private to a module, which exports a wrapper in the language's own style. `linalg.solve(A, b)` is a few lines around `dgesv_` that copy `A`, allocate `ipiv`, and turn `info` into an error.

## Standard library: core and packages

The core ships linear algebra, the elementary functions and complex arithmetic. ODE solvers and plotting are official packages, so each can be versioned and released on its own schedule.

| Component | Where | Contents |
| --- | --- | --- |
| Prelude | Core, no import | Arithmetic, `exp`, `log`, `sin` … `atanh`, `sqrt`, `abs`, `floor`, `round`, `div`, `mod`, `factorial`, `sum`, `prod`, `mean`, `min`, `max`, `all`, `any`, `zeros`, `ones`, `eye`, `linspace`, `rand`, `size`, `length`, `adjoint`, `dot`, `isequal`, `int`, `real`, `complex`, `string`, `typeof`, `isa`, `append`, `dict`, `get`, `keys`, `haskey`, `keep`, `reshape`, `eltype`, `print`, `error` |
| Complex basics | Core, prelude | `complex` type, `real`, `imag`, `conj`, `arg`, `abs` |
| Sparse basics | Core, prelude | Sparse matrix type, `sparse`, `speye`, `nnz`, `full` |
| `complex` | Core module | `polar`, `cis`, principal-branch and branch-specified `log` and `sqrt`, `isreal` |
| `linalg` | Core module | `solve`, `lstsq`, `det`, `inv`, `eig`, `svd`, `qr`, `lu`, `chol`, `rank`, `null`, `norm`, `expm`, backed by BLAS/LAPACK; sparse `lu` and `solve` via UMFPACK/KLU |
| `ode` | Official package | Explicit and stiff solvers (RK45, BDF via CVODE), events, dense output; returns a result record |
| `plot` | Official package | Line, scatter and surface plots, with styling through keyword arguments |

The packages need four things from the core: first-class functions with closures, keyword arguments, records, and FFI callbacks. All four are specified above, so `ode` and `plot` are ordinary library code with no privileged access to the runtime.

## REPL and documentation

The REPL is the main interface for exploratory work, so it shows values in a readable form:

```
> A = [1, 2; 3, 4]
A = 2×2 matrix{int}
  1  2
  3  4

> linalg.eig(A)
2-vector{real}
 -0.3723
  5.3723

> z = sqrt(-4 + 0i)
z = 0.0 + 2.0i
```

Matrices are column-aligned, large ones are elided with `⋮` and `…`, and complex values print as `a + bi`. A trailing `;` suppresses output.

### Docstrings

Lines beginning with `##` directly above a function are its docstring. The REPL command `help name` reads them from source, so no separate documentation files are needed:

```
## Euclidean norm of a real or complex vector.
## Returns a real scalar.
export function norm2(v: vector): real
  ...
end
```

## Worked example

This example solves the Lotka–Volterra model, computes the Jacobian's eigenvalues at the coexistence fixed point, and plots the trajectory.

```
import ode
import plot
from linalg import eig

p = {a: 1.0, b: 0.1, c: 0.075, d: 1.5}

f = function(t, y)
  return [p.a*y[1] - p.b*y[1]*y[2];
          p.c*y[1]*y[2] - p.d*y[2]]
end

sol = ode.solve(f, [10.0; 5.0], [0, 50], method="rk45", rtol=1e-8)

# Coexistence fixed point and its Jacobian
xs = [p.d/p.c; p.a/p.b]
J  = [p.a - p.b*xs[2],  -p.b*xs[1];
      p.c*xs[2],         p.c*xs[1] - p.d]
lambda = eig(J)          # purely imaginary pair: a centre

plot.line(sol.t, sol.y[1, :], label="prey")
plot.line(sol.t, sol.y[2, :], label="predator")
```

## Implementation

The first implementation is an interpreter. A tree-walking interpreter stabilises the syntax and semantics, and a bytecode VM replaces it once the language settles.

Once the interpreter is complete, native code generation targets [MIR](https://github.com/vnmakarov/mir), a lightweight JIT compiler with an MIT-licensed C API. Hot, annotated, type-stable functions are translated to MIR and compiled in-process, with no external assembler or linker. Functions that cannot be compiled fall back to the interpreter.

Heavy numerical work already runs in BLAS, LAPACK and the sparse solvers, so the JIT's job is the scalar loops and ODE right-hand sides around those calls. A compiled right-hand side can also be handed straight to CVODE as a native callback, skipping the trampoline.

MIR covers x86-64 on Windows, macOS and Linux and arm64 on macOS and Linux. Windows on ARM is not supported.

## Future work: automatic differentiation

Automatic differentiation (AD) will be added as a core module after the interpreter is stable. The first version uses forward mode, with dual numbers carried through ordinary arithmetic:

```
import ad

f = function(x) return x[1]^2*sin(x[2]) end
ad.grad(f, [1.0; 0.5])          # gradient vector
ad.jacobian(rhs, y0)            # Jacobian matrix
ad.derivative(sin, 0.3)         # scalar derivative
```

- **Uses.** Exact Jacobians for stiff ODE solvers, parameter sensitivities, and gradients for fitting and optimisation.
- **Coverage.** Every function written in the language, including closures and loops, is differentiable with no changes. Complex arithmetic is supported.
- **Native calls.** `extern` functions are opaque to AD. A library supplies a derivative rule for a native function with `ad.rule(name, dfn)`, and `linalg` ships rules for `solve`, `inv`, `det` and `eig`.
- **Reverse mode.** Reverse mode, which is efficient when a scalar output depends on many parameters, follows later. Type-stable functions also let the MIR JIT compile dual-number code.

## Open questions

None at present.
