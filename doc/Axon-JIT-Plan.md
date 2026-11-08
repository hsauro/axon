# Axon JIT Plan (L2)

Nov 7, 2026

This plan breaks the L2 stage of [Axon Milestones](Axon-Milestones.md#l2--mir-jit) into milestones J0 to J8. It adds native code generation through [MIR](https://github.com/vnmakarov/mir), as the [White Paper](Axon-White-Paper.md#implementation) describes. The [Language Reference](Axon-Language-Reference.md) stays the authority on behaviour: a compiled function must give the same results, output and errors as the interpreter, or the function is not compiled.

## Goals and non-goals

**Goals**

- Make scalar loops, recursive numeric functions and ODE right-hand sides fast. The heavy linear algebra already runs in BLAS, LAPACK and the sparse LU.
- Keep the interpreter as the reference implementation and the fallback. Anything the JIT cannot prove it handles exactly runs interpreted, silently.
- Keep every existing test passing in three modes: JIT off, JIT on (automatic) and JIT forced.
- Make compilation observable and testable in the project's usual style: text dumps compared against expected files, written by hand.

**Not goals in L2**

- Compiling top-level script code. Hot code must be in a function, as in Julia.
- Compiling closures that capture variables, dictionaries, strings, records, or sparse matrices. These may come later, but they are not needed for the target workloads.
- Beating BLAS. A compiled loop that does a matrix product is still slower than `*`.
- Linux. It follows the same plan once the Linux build exists.

## Decisions

### D1. Compile from the syntax tree; the bytecode VM is not a prerequisite

Decided Nov 7, 2026: the L2 list no longer starts with "a bytecode VM replaces the tree-walker". The reasons:

- The JIT does not need a VM. It needs typed function bodies, and it gets them by lowering the syntax tree of one function into a small typed IR (D3).
- A VM rewrite touches every construct and all 380 tests, without making the hot loops much faster. A good VM is typically 2–5 times faster than a tree-walker; MIR code is typically 20–100 times faster on scalar code.
- The tree-walker stays the reference implementation, which makes the "same behaviour" rule easy to check.

If a VM is still wanted for cold code, it can come after L2 without affecting the JIT.

### D2. MIR as a DLL, built from source, with a small C shim

Settled in J0:

- **What is built.** MIR v1.0.0 (May 2024, the latest release): only `mir.c` and `mir-gen.c` (the MIR API, the generator and the MIR interpreter), not `c2mir`. Axon's shim, `src/native/axmir.c`, is compiled into the same library.
- **Windows.** `tools/build_mir.cmd` clones the tag into `third_party/mir` (gitignored) and builds `lib/win64/mir.dll` with MSVC 2022, through Axon's own `tools/mir/CMakeLists.txt`. The C runtime is linked statically, so the DLL (630 KB) imports only `KERNEL32.dll`. MIR calls Windows x86-64 unofficial, but its Windows code paths exist and the self-test passes.
- **Why a shim.** Most of MIR's API takes and returns pointers and integers, and Delphi binds those directly. The exception is `MIR_op_t`, the operand. It uses enum bitfields, which MSVC and clang lay out differently (56 against 48 bytes), and MIR returns it by value and takes it through varargs. The shim takes operands as `axmir_op`, a plain 48-byte record, and builds the `MIR_op_t` array itself. It also:
  - looks up instruction codes by name, so Delphi does not copy MIR's enum ordinals;
  - replaces MIR's error function, which would exit the process, with a handler set from Delphi;
  - gives access to the fields of `MIR_item`.
- **Loading.** Like OpenBLAS: loaded on first use (`MirAvailable`), with the symbols bound as procedure variables, so the interpreter runs everything without the library.
- **Static linking: not on Windows.** MIR's objects need `setjmp`/`longjmp`, `fopen`/`popen`, `strtoull` and `__chkstk`, and Delphi's `System.Win.Crtl` provides none of them. The DLL stays, as it did for OpenBLAS and CVODE.
- **macOS ARM64.** Build `libmir.dylib` (or a static `libmir.a`, which Delphi links on macOS as it does Skia) with clang and the same `tools/mir/CMakeLists.txt`. The host must be signed with the `com.apple.security.cs.allow-jit` entitlement; RoadRunner_Delphi_JIT already went through this with SLJIT.

### D3. A typed IR between the syntax tree and MIR

The syntax tree is lowered to **JIR**, a small typed IR in Delphi, and only JIR is translated to MIR. The steps:

- **Type inference.** Starting from the parameter types, every expression gets one static type: `bool`, `int`, `real`, `real vector`, `int vector` or `real matrix`. A construct with no rule yet, or a type that would depend on values, rejects the function, with a reason.
- **Value-dependent types are the main trap.** `n ^ k` with `int` operands is an `int` when `k >= 0` and a `real` otherwise. It compiles only when `k` is a non-negative literal or when the result is converted with `real(...)`. `int / int` is always `real`, so it is fine.
- **Dumps.** `axon --jir file.sci` prints the typed IR of each function, or the reason it was rejected. Tests compare that output against hand-written `.jir` files, like `--ast` today, and none of these tests need MIR.

### D4. Errors leave compiled code by return status, never by exception

Delphi exceptions cannot unwind through MIR-generated frames on Win64, because they have no registered unwind tables. So:

- **Status returns.** Every compiled function returns a status word alongside its results.
- **Raising an error.** Generated code calls a runtime helper `rt_error(kind, site)`, which records a pending error, and then returns a failure status.
- **Calls between compiled functions.** On a failure, the caller records its call site, `rt_frame(site)`, and returns failure too.
- **Rebuilding the error in Delphi.** Back in the interpreter, the pending error is raised as a normal `EAxonError`. The recorded sites rebuild the trace (`file:line:col in name`), so traces are identical to the interpreter's.
- **Runtime helpers.** Any helper that can fail (allocation, indexing, calls back into the interpreter) catches Delphi exceptions itself and turns them into a status. The FFI already does the same for callbacks, with pending errors.

### D5. Arithmetic semantics are emitted exactly

- **`int`.** `+`, `-` and `*` check for overflow and raise `OverflowError`, with MIR's `addo`/`subo`/`mulo` followed by a `bo` branch. The J0 self-test confirms them.
- **Division.** `div` and `mod` are floored. An `int` divisor of zero raises `DomainError`.
- **`real`.** Real arithmetic is IEEE 754: no traps, so `Inf` and `NaN` propagate. `sqrt(-1.0)` is NaN, never an error.
- **Conversions.** `floor`, `ceil`, `round` and `int` raise on NaN or on a value outside the 64-bit range, as the reference says. `round` rounds halves away from zero.
- **Elementary functions.** They call the same Delphi routines the interpreter uses, through the runtime helper table. Results are then bit-identical, not just close.

### D6. When a function is compiled

- **Mode.** `--jit=off|on|force` on the command line, or the environment variable `AXON_JIT`. The default is `off` until J5 is done, then `on`.
- **`on`.** A function is compiled at its first call when every parameter is annotated with a supported type, and when inference accepts the body. Compiling is cheap: MIR's author measures about 0.25 ms for a sieve. So there is no call-count threshold, at least at first.
- **Cache.** The compiled code is kept per function and per argument-type signature. A call whose argument types do not match the annotations runs interpreted, as now.
- **`force`.** `force` additionally specialises unannotated functions on the runtime types of their arguments (J6). It also reports how many calls ran compiled, so the test suite proves it exercises the JIT.
- **For tests.** `__jit_compiled(f)` returns `true` once `f` has compiled code, like `__copies()`.

### D7. Boxed boundary, unboxed inside

- **Entry.** The interpreter calls compiled code through one generated entry thunk per function, `status entry(args*, results*)`. The thunk unboxes `TAxValue` slots into machine values and calls the typed body.
- **Calls between compiled functions.** These call the typed bodies directly, with no boxing.
- **Arrays.** Arrays are passed as `(data pointer, rows, cols, object)`. The first write to an array parameter calls a copy-on-write helper, which applies the same `RefCount > 1` rule as `AssignArraySlot`. New arrays are allocated through a helper that returns a `TArrayObj`.

## Milestones

Each milestone ends with every test passing with the JIT off, on and forced, on Windows. The macOS check follows the M0 rule: a manual run before the milestone is closed. Tests go in `tests/jNN/`. J0 extends `IsMilestoneDir` in the test runner to accept `j` folders.

### J0 — MIR spike and bindings

- [x] MIR v1.0.0 fetched by `tools/build_mir.cmd` into `third_party/mir` (gitignored); `lib/README.md` records the source and licence (MIT)
- [x] `mir.dll` built with MSVC 2022 from `mir.c`, `mir-gen.c` and the shim `src/native/axmir.c`, through `tools/mir/CMakeLists.txt`
- [x] Static linking tried and ruled out on Windows (D2)
- [x] `Axon.Native.Mir.pas` binds the API in use: modules, functions, prototypes, imports, labels, instructions through the shim, loading, linking and generation
- [x] `axon --jit-selftest` builds three functions with the API, links and generates them, calls them through function pointers, and checks the results:
  - `add_checked`, overflow-checked `int` addition
  - `sum_to`, a real loop over `1..n`
  - `fib`, recursion through MIR calls
- [x] Overflow branches confirmed (D5). A Delphi helper is called from MIR code, and the error status is returned through it (D4)
- [x] Baseline timings recorded for the first benchmarks in `bench/`, run by `bench.cmd` (below)
- [ ] The same self-test passes on macOS ARM64 with `libmir.dylib` and the `allow-jit` entitlement

### J1 — Typed IR and inference (no code generation yet)

- [x] `src/Axon.Jit.Ir.pas`: JIR, a linear list of three-address instructions over typed virtual registers, with labels and branches. Instructions that can fail carry a site, the line and column of the innermost enclosing statement, which is where the interpreter locates errors raised without a position
- [x] `src/Axon.Jit.Lower.pas`: the syntax tree of one function lowered to JIR. It covers:
  - scalar `bool`, `int` and `real` parameters and locals, and literals
  - arithmetic with promotion, comparisons, and `and`/`or`/`not` with short-circuiting
  - `if`/`elseif`/`else`, `while`, and `for` over `int` and `real` ranges
  - `break`, `continue` and `return`
  - `local`, and `x: T = e` with widening
- [x] Inference rejects with a reason and a position, for example:
  - "x is int at 6:3 and real at 7:3"
  - "int ^ int with a variable exponent …"
  - "reads offset, which is not a local variable"
  - "y may be read before it is assigned"
  - "returns int at 46:5 but can also reach the end and return nothing"
- [x] `axon --jir file.sci` dumps every top-level function, and `.jir` tests (`tests/j01`, expected output written by hand) cover lowering and rejections. The test runner accepts `jNN` folders and `.jir` expected files

Resolving names statically needs care, because the interpreter resolves them at run time. A plain assignment creates a variable in the function's outermost scope when it first runs (rule 5), and a read of a name that has no local variable goes to the module (rule 6). So JIR accepts a read only where the variable is *definitely assigned* on every path. This is tracked structurally:

- after an `if`, the intersection over the branches that fall through;
- after a loop, what held before it, since the body may run zero times.

Any other read could reach the module at run time, so the function is rejected. `local`, `x: T = e` and the loop variable of a `for` live in their block (rules 2 and 3); a later `local` of the same name shadows, and the dump shows it as `name.2`. Two more rules keep compiled code identical to the interpreter:

- The bounds of a `for` range are copied before the loop, so assignments in the body cannot change the iteration, as the interpreter's range object guarantees.
- Element k is computed as `start + k*step`, exactly as `TRangeObj.ItemAt` does, not by accumulating.

### J2 — Scalar code generation

- [x] `src/Axon.Jit.Mir.pas`: JIR translated to MIR, generated and linked in one MIR context for the process. Each function is a module with two functions: a typed body `f<id>(res, params…)` returning a status, and an entry thunk `e<id>(args, res)` that loads 8-byte argument slots and calls the body (D7)
- [x] Exact arithmetic (D5):
  - checked `int` `+`, `-`, `*` and unary `-` with `addo`/`subo`/`mulo` and `bo`;
  - `int ^ literal` as IntPow's square-and-multiply with checked products, so it overflows exactly when the interpreter does;
  - `real ^` through a helper with RealArith's rule;
  - range counts through helpers with MakeRange's code;
  - range elements as `start + k*step`.

  `div` and `mod` are calls, so they come in J3
- [x] Runtime-error path (D4). A failing instruction branches to an error block that calls `rt_error(fid, site, code)` and returns status 1; a failing helper records its own error. The interpreter raises the pending error at its site inside Invoke's frame handling. Tests in `tests/j02` check, with `.err` files, that reports and traces are identical to the interpreter's (verified against interpreted runs too)
- [x] Modes `--jit=off|on|force` and `AXON_JIT`; the default stays `off` until J5. Built-ins for tests:
  - `__jit_compiled(f)`
  - `__jit_reason(f)`
  - `__jit_mode([m])`, which switches the mode inside a test, so a file can run the same function compiled and then interpreted and compare

  `AXON_JIT_LOG=file` records every compile decision
- [x] The full suite passes with the JIT off, on and forced (394 tests each). Only 13 functions of M0–M13 compile at this stage, so `tests/j02` holds the tests that exercise compiled code: arithmetic, comparisons including NaN, short-circuiting, int and real ranges, `break`/`continue`, `while`, and every error kind

J2 measurements, on Win64 Release (`AXON_JIT=on bench.cmd`):

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `harmonic(100000)` | 88.2 ms | 108 µs | 817× |
| `mandel(60, 50)`: `escape` compiled, `mandel` still interpreted | 193 ms | 19.4 ms | 10× |

The other kernels need calls (`fib`, `ones` in `sieve`) or arrays (`matmul`) and are unchanged until J3 and J4.

### J3 — Calls

- [x] Calls between compiled functions, including recursion. A called name resolves in the function's defining scope, as the interpreter's lookup would. Compiled code is generated in groups: the session lowers a function and the functions it calls, and the group is generated and linked at once. Each body is exported as `f<id>`, and calls go directly to it:
  - **Guard.** A guard checks that the module variable still holds the function the call was compiled against; after rebinding, the call goes through the interpreter.
  - **Call depth.** The interpreter's call-depth counter is raised and checked around the call, as `Invoke` does, so `RecursionError` comes at the same depth with the same 10,000-frame trace.
  - **Recursion.** Recursion compiles when the result type is known before the recursive call: declared, or fixed by an earlier `return`. Mutual recursion goes through the interpreter in one direction.
- [x] Built-ins with scalar arguments:
  - **Elementary functions** (`sqrt` … `atanh`) call the interpreter's own real routines directly (`ElementaryRealFunction` in `Axon.Builtins`), so the result has the same bits.
  - **`abs`, `floor`, `ceil`, `round`, `int`, `real`, `min`, `max`, `div` and `mod`** call the built-in itself through `rt_call`. This is exact by construction, errors included.
- [x] Multiple return values, `return a, b`, and multiple assignment from a call, `[q, r] = f(x)`
- [x] Calls to functions that do not compile go through the interpreter (`rt_call` boxes the arguments and calls `CallValue`), so an uncompilable callee does not stop its caller compiling. The callee's result type must be declared, or the result unused
- [x] `print` and `error` from compiled code, with numbers and string literals, through `rt_call`
- [x] Errors through any mix of frames. The function where an error starts records it, as a kind and message or as the exception an interpreted call raised. Each compiled caller adds its call site (`rt_frame`). `TakeJitError` builds the trace exactly as the interpreter would. Tests in `tests/j03` cover errors from a compiled callee, from an interpreted function between compiled ones, from a built-in, from `error`, and from recursion depth; all are checked against interpreted runs too

Known limits: the elementary-function shortcut assumes a prelude name is not shadowed by a module variable created after the caller compiled. A compiled function returning several values that is rebound to another function is reported as a `TypeError` rather than called.

J3 measurements, Win64 Release:

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `fib(22)` | 134 ms | 223 µs | 600× |
| `harmonic(100000)` | 88.5 ms | 108 µs | 820× |
| `mandel(60, 50)` | 196 ms | 216 µs | 900× |

In the full suite with the JIT forced on, 50 functions compile (13 after J2). Most of the rest have unannotated parameters, which is J6.

### J4 — Arrays

- [ ] `real` and `int` vectors and `real` matrices as parameters, locals and results
- [ ] Indexing `v[i]`, `A[i, j]` and `end` inside an index, with the reference's bounds checks and `IndexError` messages
- [ ] `length`, `size`, `zeros`, `ones`, and element writes `v[i] = x` with copy-on-write (D7). `__copies()` counts stay exactly the same as interpreted
- [ ] Whole-array operations (`+`, `.*`, `*`, `sum`) call the existing `Axon.Arrays`/BLAS routines through helpers instead of compiling them

### J5 — Turn it on

- [ ] Default mode becomes `on`
- [ ] The full suite passes in all three modes, and the test runner can run all three (`test.cmd -jit`)
- [ ] The IDE's Run uses the default. The Output pane can show which functions compiled (an `AXON_JIT_REPORT` line, like `show`)
- [ ] The reference gains a short "Compilation" section: what compiles, that results are identical, and how to check with `--jir`

### J6 — Specialisation of unannotated functions

- [ ] At a call, an unannotated function is specialised on the concrete argument types, then cached per signature
- [ ] Inference is shared with J1, so the rejection rules are unchanged
- [ ] A limit on specialisations per function, with interpretation beyond it

### J7 — ODE right-hand sides

- [ ] `ode.solve` with `rk45` runs its stepper loop compiled, once `ode.sci`'s helpers compile
- [ ] For `bdf`, a compiled `f(t, y)` is handed to CVODE through a generated native wrapper, `int rhs(t, y, ydot, user)`, which reads and writes the `N_Vector` data directly, skipping the trampoline and the per-call array boxing
- [ ] Results identical to interpreted runs within the solver tolerances, checked with the `tests/m10/testing.sci` helpers

### J8 — Benchmarks and closing

- [ ] `bench/` holds the benchmark programs, run by `bench.cmd`, which prints interpreted against compiled timings from `time.bench`:
  - recursive `fib(25)`
  - a scalar sum loop
  - the sieve of Eratosthenes
  - the Mandelbrot set
  - a naive triple-loop matrix product, against BLAS `*`
  - n-body
  - the Lotka–Volterra `ode.solve` with `rk45` and with `bdf`
- [ ] Results recorded in this document, with the machine, the sizes, and best-of-5 per call
- [ ] Target: at least 20 times faster than interpreted on the scalar-loop benchmarks. This is a target, not a promise: report what is measured
- [ ] macOS ARM64 run of the suite in all three modes and of the benchmarks
- [ ] `Axon-Milestones.md` L2 items ticked or rewritten to match what was built

## Baseline (today's interpreter)

Measured in J0 before any JIT work: `bench.cmd` on Win64 Release, on an Intel Core i9-9900X at 3.5 GHz. The figures are best of 5 per call, from `time.bench`. The kernels' parameters are annotated, so the JIT can compile them unchanged.

| Kernel (`bench/`) | Interpreted |
| --- | --- |
| `fib(22)`, recursive | 128 ms |
| `harmonic(100000)`, a scalar loop | 88.8 ms |
| `sieve(100000)`, vector reads and writes | 376 ms |
| `mandel(60, 50)`, real arithmetic and calls | 189 ms |
| `matmul` of two 60×60 matrices, triple loop | 467 ms |
| The same product with BLAS `*` | 36 µs |

The J0 self-test gives a first sign of the gap: `fib(25)`, hand-written in MIR, runs in 0.6 ms. Interpreted, it would take about 128 ms × 11 ≈ 1.4 s. Building and generating its three test functions takes about 1.3 ms in all.

## Risks

| Risk | Mitigation |
| --- | --- |
| MIR on Windows is unofficial | J0 is a spike before any dependent work; MIR's CMake already has a Windows shared-library target; clang is available as well as MSVC |
| Exceptions cannot cross JIT frames | Status-return protocol (D4) from J2 onwards; helpers never let exceptions escape |
| Subtle differences in semantics | The interpreter is the oracle: every test runs in three modes, and the elementary functions call the same Delphi routines |
| macOS hardened runtime | `allow-jit` entitlement and MIR's existing Apple M1 support; done before in RoadRunner_Delphi_JIT |
| Scope creep into a general compiler | Reject early and fall back; the target workloads are listed in J8 |
