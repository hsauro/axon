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

- **Mode.** `--jit=off|on|force` on the command line, or the environment variable `AXON_JIT`. The default was `off` until J5 and is now `on`.
- **`on`.** A function is compiled at its first call when every parameter is annotated with a supported type, and when inference accepts the body. Compiling is cheap: MIR's author measures about 0.25 ms for a sieve. So there is no call-count threshold, at least at first.
- **Cache.** The compiled code is kept per function and per argument-type signature. A call whose argument types do not match the annotations runs interpreted, as now.
- **`force`.** `force` behaves as `on` (specialisation of unannotated functions, J6, applies to both). `AXON_JIT_LOG` shows which functions a run compiled.
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

The other kernels needed calls (`fib`, `ones` in `sieve`) or arrays (`matmul`), which J3 and J4 added.

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

- [x] `vector{real}`, `vector{int}` and `matrix{real}` as parameters, locals and results. The element type must be declared, because a plain `vector` or `matrix` can hold any element type; the message says so, and J6 will specialise on the type at run time instead
- [x] Values and reference counts (D7):
  - **Frames.** Each array register is a `TAxValue` slot in a frame the function allocates on entry and releases at its single exit, on every path.
  - **Parameters.** A body takes its own reference to each array parameter, as `Invoke`'s parameter cell does.
  - **Moves.** Moving from a temporary transfers the reference, while assigning from a variable shares it.

  Reference counts are therefore the interpreter's, and so are copy-on-write decisions and `__copies()` counts. `tests/j04` checks the counts against interpreted runs: a shared argument, a write to the array being iterated, and arrays that must not be copied
- [x] Indexing `v[i]`, linear `A[k]`, `A[i, j]` and `end`, read and written inline from the `TArrayObj`'s fields; their offsets are measured at start-up. Each index is checked as soon as it is evaluated, as `EvalIndexItem` does, with the same `IndexError` message and position. A write first checks the reference count and copies through `rt_make_unique` when the array is shared. It never widens the array: a value that would widen it is rejected, and a `bool` stored in an `int` vector converts, as `Put` does. Ranges, colons and masks as indices are not compiled yet
- [x] `length`, `size(A)`, `size(A, 1)` and `size(A, 2)` inline. `zeros`, `ones`, `sum` and `print` of arrays go through the built-ins
- [x] Operators on real arrays go to `Axon.Ops` through `rt_call`, so they give the same results and errors. The shapes covered: array with array (`+ - .* ./`), array with number, number with array, matrix `*` matrix or vector, and unary `-`. The result's type is checked at run time
- [x] `for x in v` over the elements of an array, holding it for the loop as the interpreter does

J4 measurements, on Win64 Release. `bench/matmul.sci` now declares `matrix{real}` parameters; it takes the same time interpreted.

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `sieve(100000)` | 373 ms | 743 µs | 500× |
| `matmul` of two 60×60 matrices, triple loop | 472 ms | 397 µs | 1190× (BLAS: 35.5 µs) |

Every kernel in `bench/` now compiles. In the full suite with the JIT forced on, 85 functions compile (50 after J3).

### J5 — Turn it on

- [x] The default mode is `on`. `--jit=off` or `AXON_JIT=off` turns the JIT off
- [x] `test.cmd -jit` runs the full suite with the JIT off, on and forced; all three pass
- [x] IDE:
  - **Toggle.** **Run > Use JIT Compiler** and a **JIT** toolbar button switch between compiled and interpreted runs, so the same program can be timed both ways. The IDE passes the choice to the programs and the REPL it starts through `AXON_JIT`, and keeps it in `settings.ini`. The Running line says which mode is used.
  - **Report.** With `AXON_JIT_REPORT` set, `axon` writes each compile decision to stderr as a `#3jit …` line, like `#3show`. After a run, the Output pane lists the functions compiled, and the reason for each that ran interpreted.
  - **Example.** `examples/09_jit.sci` (on the welcome screen) times four kernels for the comparison. Compiled, they take 1.6–3.4 ms (compile time included); interpreted, 377 ms – 1 s.
- [x] The reference has a "Compilation" section: what compiles, that results are identical, what stays interpreted, `--jit`, `AXON_JIT`, `--jir`, and how rebinding behaves. The IDE help (`help/ide.md`) explains the toggle

### J6 — Specialisation of unannotated functions

- [x] A parameter without an annotation, or annotated plain `vector` or `matrix`, takes the argument's type:
  - **From the interpreter.** When the interpreter calls the function, the type comes from the bound value. `Invoke` keeps a code per set of argument types on the `TFunctionObj`, and the last set is checked first, so a function called the same way each time costs one comparison per argument.
  - **From compiled code.** A compiled call specialises its callee on the static types of its arguments.

  The session keys its entries by function and parameter types (`SignatureFor`, `SignatureKey`). Logs and the IDE report name specialisations with their types, as in `sq(real)`
- [x] Inference is J1's: an unannotated parameter is an untyped variable, so a body that changes its type is rejected for that signature only. For example, `changes(int)` runs interpreted while `changes(real)` compiles
- [x] At most eight specialisations per function (`MaxSpecialisations`); calls with further argument types run interpreted, with the reason given
- [x] `--jir` prints, after the top-level functions, the specialisations that calls in the file created. `tests/j06` covers the dump, results against interpreted runs (recursion, scalars, plain `matrix` and `vector`, a parameter that changes type, the limit), and an error trace through a specialised function

In the full suite with the JIT forced on, 127 functions compile (85 after J4). Most of the remaining rejections are calls with arguments of types the JIT does not compile, such as strings, lists and records.

### J7 — Fast ODE solves

**Profiling changed the plan.** The original J7 would have compiled `f` and handed it to CVODE natively. Profiling Win64 Release showed this would barely help, because a solve's time goes into the solver's own interpreted Axon code: per-step slices, growing storage, a closure per step, record and list operations, and the `call_rhs` checks.

| Solve | Time per evaluation of `f`, overall | `f` itself |
| --- | --- | --- |
| Lotka–Volterra, `rk45` (3608 evaluations, 175 ms) | 48.6 µs | 5.8 µs (12%) |
| Robertson, `bdf` (592 evaluations, 122 ms) | 206 µs | 6.8 µs (3%) |

**Decision (Nov 7, 2026).** The solver loops move into Delphi, as a native core module `odecore`, the way CVODE is native. `stdlib/ode.sci` keeps the API: argument checks, the result record, and `sol.at` from the per-step data. The native loops reproduce the Axon code operation for operation, so step counts and results are unchanged. This revises the White Paper's "RK45 written in Axon".

- [x] **J7a.** The RK45 stepper in `odecore` (`src/Axon.OdeCore.pas`): Dormand–Prince 5(4) with step-size control, DOPRI5 dense output, `t_eval`, events located with the Illinois method, and terminal events. It calls `f` and the event functions as the interpreter does, with `call_rhs`'s checks and messages. A right-hand side that returns a scalar for one equation is now accepted, as the reference says; the Axon code had rejected it
- [x] **J7b.** The BDF loop in `odecore`: CVODE called from Delphi (`src/native/Axon.Native.Cvode.pas`), with cdecl right-hand-side and root callbacks that find their solve through CVODE's user data, so solves nest without `current`. A callback never lets an exception into CVODE: it keeps the exception and returns -1, and the loop re-raises it. `ode.sci` lost its `extern` blocks and glue, and keeps the API, the result record and `sol.at`
- [x] Both loops reproduce the Axon code operation for operation. A comparison against the old `ode.sci` gives identical step and evaluation counts, and zero difference in every output value, `t_eval` point, `sol.at` value and event, for these cases:
  - Lotka–Volterra
  - backward integration
  - `t_eval` output
  - events, including a terminal one
  - `first_step` and `max_step`
  - the stiff Robertson problem
  - a solve nested inside a right-hand side
- [x] **J7c.** Compiled right-hand sides:
  - **Captures.** Closures compile, and so do reads of captured and module values and their field paths (`p.a`). Captures are hidden parameters read on entry, and are exact because the function runs nothing that could change them.
  - **Literals.** Vector and matrix literals compile.
  - **Fast calls.** `Invoke` has a fast path (`FastCall`) for compiled code that takes its arguments as they are: no scope or parameter cells, and no file switch. It cuts a trivial compiled call from 736 ns to 333 ns.
  - **Capture cache.** The cells captures are found in are cached per function object, valid while no scope of the chain gains a name.

  `tests/j07` covers captures that change value and type, field paths, a closure assigning outward, the rule-5 shadowing case, literals, error traces, and ODE solves compiled against interpreted

J7 measurements, Win64 Release:

| Solve | Axon loops | Native loops (J7a, J7b) | Plus compiled `f` (J7c) |
| --- | --- | --- | --- |
| Lotka–Volterra, `rk45` (3608 evaluations) | 175 ms | 23.3 ms | 8.75 ms (20×) |
| Robertson, `bdf` (592 evaluations) | 122 ms | 6.58 ms | 4.31 ms (28×) |

What remains per evaluation is mostly the call itself: about 0.4 µs for a compiled call, plus the arrays for `y` and the result. Calling compiled right-hand sides with raw vectors would take it further.

### J8 — Benchmarks and closing

- [x] `bench/run.sci`, run by `bench.cmd`, times every kernel interpreted and compiled in one process (switching with `__jit_mode`), and checks that both give the same result (`isequal`). The kernels:
  - recursive `fib`
  - a scalar sum loop
  - the sieve of Eratosthenes
  - the Mandelbrot set
  - a naive triple-loop matrix product, against BLAS `*`
  - n-body
  - the Lotka–Volterra `ode.solve` with `rk45`, and the Robertson problem with `bdf`

  The sizes keep the interpreted runs short: the whole table takes about 30 s. The per-kernel scripts of J0 are gone
- [x] Results recorded below
- [x] Target met: every scalar-loop kernel is 469 to 1120 times faster than interpreted, against a target of at least 20
- [ ] macOS ARM64: build `libmir.dylib` there (`tools/mir/CMakeLists.txt`, clang), sign the host with `allow-jit`, and run `axon --jit-selftest`, `test -jit` and the benchmarks. This needs the Mac
- [x] `Axon-Milestones.md` L2 rewritten to match what was built

**Results.** Win64 Release, Intel Core i9-9900X at 3.5 GHz, `bench.cmd`, Nov 7, 2026. Each figure is the best of 5 runs, per call (`time.bench`), so it excludes compilation, which happens at the first call. In every row the compiled and interpreted results are identical.

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `fib(22)`, recursive | 132 ms | 223 µs | 590× |
| `harmonic(100000)`, scalar loop | 88.9 ms | 107 µs | 828× |
| `sieve(100000)`, vector reads and writes | 373 ms | 795 µs | 469× |
| `mandel(60, 50)`, real arithmetic and calls | 191 ms | 211 µs | 905× |
| `matmul` of two 60×60 matrices, triple loop (unannotated, specialised) | 465 ms | 415 µs | 1120× |
| `nbody(1000)`, five bodies | 209 ms | 303 µs | 688× |
| `ode.solve`, Lotka–Volterra, `rk45` | 22.6 ms | 5.63 ms | 4× |
| `ode.solve`, Robertson, `bdf` | 4.84 ms | 1.13 ms | 4× |
| The same 60×60 product with BLAS `*` | 36.2 µs | | |

The ODE rows compare the right-hand side interpreted and compiled. In both columns the solver loops are J7's native ones. Against the solver as it was before L2, with its loops in Axon, the gains are 31× (175 ms to 5.63 ms) and 108× (122 ms to 1.13 ms).

### J9 — Records

Done Nov 10, 2026: the first step of moving more of the language onto the JIT (CLAUDE.md, "Direction"). Lists follow as J10, on the same groundwork.

**Types: record shapes.** A record compiles as its *shape*: its field names in order, the JIR type of each field, and, for a record of a declared type (`record T … end`), that type. `TJType` becomes an integer type: the existing types keep their numbers, and each shape is entered once in a process-wide table (`Axon.Jit.Ir`) and gets its own number, from 16 up, so equal shapes are equal types and the existing comparisons keep working. The text form is `record{a: real, y: vector{real}}`, or `T{…}` for a declared type. A field of a type the JIT does not compile (a string, a list) is typed `other`: the record still compiles, but that field cannot be read or written.

- **From values.** `JTypeOfValue` gives a record's shape, recursively for nested records. At a call, the interpreter checks the arguments against the compiled types structurally (`JTypeMatches`), without building the shape, so the check costs a comparison per field, not an allocation. An `other` field matches any value.
- **Specialisation.** An unannotated record parameter takes the argument's shape, as J6 does for arrays. A parameter annotated with a declared record type takes it too, when the argument is a record of that type (checked against the type the annotation names in the function's scope). The session's signature keys use type numbers, not names.

**Values.** A record register is a value slot in the frame, as an array register is (J4): reference-counted, shared on assignment from a variable, moved from a temporary, held by the body for a parameter, released at the single exit. Records pass to and from compiled functions by slot address, and to the interpreter boxed (`RtCall`, `RunCompiled`).

**What compiles.**

- [x] Record parameters (unannotated, or annotated with a declared record type), locals and results (unannotated results; a declared record result type stays rejected for now); whole records read from outside (captures)
- [x] Field reads `r.a`, `r.a.b`, on locals and parameters: inline, the field's position fixed at compile time. A field missing from the shape (the interpreter's `FieldError`) or of type `other` rejects the function
- [x] `r.y[i]`, `r.M[i, j]`, `length(r.y)` and `size(r.M, …)` read through the path, without a temporary copy of the array reference, so reference counts and `__copies()` stay the interpreter's
- [x] Field writes `r.a = x`, `r.a.b = x`, and element writes `r.y[i] = x`, as `AssignPath` does: the value first, then each record on the path made unique if shared (copy-on-write, `MakeUnique`), then the write. The value must have the field's type, since a compiled record cannot change shape; for a declared record a narrower number widens, as the interpreter's field coercion does. Adding a field is rejected
- [x] Record literals `{a: x, b: y}`, and constructors of declared types `T(x, y)` and `T(a = x, b = y)`, with the declared field types' coercions; a field whose declared type the JIT cannot check rejects the function
- [x] Passing records to compiled callees (specialised on the shape) and to interpreted ones; `print` of records
- [x] A temporary holding a field's array or record (an argument `f(r.y)`, an operand `r.y + 1.0`) is released right after its use, so it does not keep a reference the interpreter would not hold

**Not in J9.** Comparing records (`==`), `isa` and `typeof`, adding fields, a declared record result type, records inside lists (J10).

**Runtime helpers.** `rt_new_record(dst, shape, args)` builds a record from its field values in the argument slots, with the declared type set as `CoerceRecord` sets it; `rt_record_unique(slot)` copies a shared record, as `MakeUnique`. Field addresses are computed inline from `TRecordObj`'s layout, measured at start-up in `ComputeLayout` as the array layout is.

**Tests.** `tests/j09`: `.jir` dumps of field reads, writes, paths and construction; results compiled and interpreted (`__jit_mode`) for every construct; copy-on-write (a record shared with another variable, a parameter written, a nested record shared) with `__copies()` for arrays in records; errors (an index out of bounds through a field) with their traces; rejections with their reasons. The whole suite in all three JIT modes.

**Rebinding.** A constructor is checked, when it runs, to be the record type the function was compiled against (the variable that held it, as calls are guarded). A file's record types are defined before it runs, so this matters only in the REPL, where defining a record type again makes a compiled function that constructs it raise `TypeError` (`tests/j09/redefined.repl`).

**Results.** `bench.cmd`, Win64 Release, i9-9900X, Nov 10, 2026; both kernels give identical results compiled and interpreted.

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `record_steps(2000)`: state `{t, y, steps}`, ten elements of `s.y` updated per step | 67.7 ms | 77.8 µs | 870× |
| `ode.solve`, Lotka–Volterra, `rk45`, right-hand side reading a declared parameter record passed with `params` | 26.3 ms | 5.33 ms | 5× |

The second row compares the right-hand side interpreted and compiled, as the J8 ODE rows do; compiled, the solver calls it directly. With the JIT forced on, the tests, examples and benchmarks compile 290 functions. Most rejections that remain involve strings and lists, including records with string or list fields that a function reads (the plot module's figure records): J10 and string support.

### J10 — Lists

Done Nov 10, 2026, after J9, on the same groundwork.

**Types: lists of one element type.** A list compiles when all its elements have one compiled type: `list{real}`, `list{vector{real}}`, `list{record{t: real, y: vector{real}}}`, and lists of lists. Its type is entered in the type table as record shapes are. A list mixing types does not compile. The empty list is `list{?}`, a list whose element type is not known yet; at a call, an empty list also matches any `list{T}`, since code compiled for elements of type T handles no elements as well.

- **`{}` followed by appends.** The common pattern is `l = {}`, then `l = append(l, x)` in a loop. When a variable that holds `list{?}` from an empty literal is then given a `list{T}`, the lowering notes T for that literal and lowers the function again, so the literal is `list{T}` from the start. Other uses of an empty list whose element type stays unknown reject the function.
- **Checks at a call.** Checking that a list argument is uniform looks at every element, as a record check looks at every field. A list's element type could be remembered, but every in-place change of a list in the interpreter would then have to forget it, and a missed one would let compiled code read an element as the wrong type; so J10 checks, and a cache can follow if the cost shows up.
- **Annotations.** A parameter annotated plain `list` takes the argument's list type, as plain `vector` does.

**Values.** A list register is a value slot, as arrays and records are (J4, J9).

**What compiles.**

- [x] List parameters, locals, results and captures; lists inside records, and records inside lists
- [x] Literals `{a, b, c}` of one type, and `{}` as above
- [x] `l[i]` and `l[end]` with an int index, checked as the interpreter checks it (`IndexError` at the index); `length(l)` inline; through a record's field too (`s.items[i]`, `length(s.items)`)
- [x] `l[i] = x` with x of the element type, the list copied first if shared (`MakeUnique`); a value of another type would make the list mixed, and rejects the function
- [x] `append(l, x)`, and `l = append(l, x)` growing the list in place when nothing else holds it, as the interpreter's `ExecAppendAssign` does
- [x] `for x in l`, holding the list for the loop as the interpreter does
- [x] `l[i].a`: a field of a record element, read (writing through a list element waits)

**Not in J10.** Ranges and masks as list indices (sublists), `l[i].a = x` and other writes through an element, comparing lists, `sort` and the other built-ins on lists, dictionaries.

**Runtime helpers.** `rt_new_list(dst, elem, args, n)`, `rt_list_append(dst, src, arg, elem, in_place)`, `rt_list_unique(slot)`. Elements are read and written inline from `TListObj`'s items, whose length sits before the first element (measured at start-up).

**Tests.** `tests/j10`, in the style of `tests/j09`: dumps; results and copies against the interpreter (shared lists written, a parameter appended to, appends in place); `{}` then appends; lists of records and records holding lists; errors; rejections. The whole suite in all three JIT modes.

**Results.** `bench.cmd`, Win64 Release, i9-9900X, Nov 10, 2026; all identical compiled and interpreted.

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `list_build_sum(10000)`: `l = {}`, 10000 appends, then `for x in l` sums | 22.5 ms | 1.15 ms | 20× |
| `particles(100, 50)`: a list of 100 records `{x, v}`, each replaced by a new record per step | 15.9 ms | 1.71 ms | 9× |

The speed-ups are smaller than for loops over numbers because the work is allocation: an append grows the list's items by one (about 110 ns, the same `SetLength` the interpreter's in-place append uses), and the particles kernel builds a record per element per step. Reading is fast: summing a list of 10000 reals takes 19.6 µs, 2 ns per element, the check of the argument at the call included. That check looks at every element, so for numbers it is a tight loop over the elements' kinds (`JTypeMatches`): before that, it took 142 µs. A list could remember its element type, or keep spare capacity for appends; neither is needed yet.

With the JIT forced on, the tests, examples and benchmarks compile 321 functions (290 after J9). The commonest rejections left are function values passed as arguments, strings (and lists of strings), `global` and `typeof`.

### J11 — Strings

Done Nov 10, 2026. After J10, most functions that stay interpreted take or build strings: labels, titles and kinds passed through, messages built with `+`, `typeof` tests.

**Values.** A string register is a value slot, as an array, record or list register is: strings are reference-counted values in the interpreter too. A string literal is a constant the compiled code holds, copied into its register (`const`). `string` joins the types `JTypeOfValue` gives, so string parameters, results, record fields (`list{string}`, `{title: "…"}`) and captures compile. A parameter annotated `string` has that type.

**What compiles.**

- [x] String literals as values; strings assigned, passed, returned, and held in records and lists
- [x] `a + b` for two strings (`concat`); `+` of a string and a number is the interpreter's `TypeError`, and rejects the function
- [x] `==`, `!=`, `<`, `<=`, `>`, `>=` between strings, by `CompareStr` as `CompareOrder` and `ValuesEqual` compare them (`strcmp`). `==` between a string and a number is `false` (and `!=` `true`), as the interpreter has it; ordering them is its `TypeError`, and rejects
- [x] The string built-ins, called as the interpreter calls them (`rt_call`), with their result types known: `string`, `length`, `upper`, `lower`, `trim`, `ltrim`, `rtrim`, `replace`, `repeat`, `contains`, `startswith`, `endswith`, `find`, `split` (a `list{string}`), `join`, `format`, and `int` and `real` of a string; `print`, `println` and `error` with any strings. `string(x)` of a bool, int or real and `length(s)` of a string are common enough in loops to get their own helpers (`strof`, `strlen`), which call the interpreter's `Display` and code-point count directly
- [x] `typeof(x)`, whose result follows from x's static type, as a constant: `typeof(x) == "real"` costs a comparison

**Not in J11.** Indexing strings (`s[i]`, characters as code points), `for c in s`, string formatting built-ins beyond those listed, dictionaries.

**Runtime helpers.** `rt_str_concat(dst, a, b)` and `rt_str_cmp(a, b)` (−1, 0 or 1); `rt_str_of_int(dst, x, is_bool)`, `rt_str_of_real(dst, x)` and `rt_str_len(a)`, sharing `Display` and `StringLength` (`Axon.Builtins`) with the interpreter; constants are values the compiled code owns (`TJitCode.Consts`). A string argument to `rt_call` is boxed from its register, or from the literal when the call site holds one (`print("…")`).

**Tests.** `tests/j11`: dumps; results against the interpreter; errors from string built-ins with their traces (`int("x")`); rejections. The whole suite in all three JIT modes.

**Results.** `bench.cmd`, Win64 Release, i9-9900X, Nov 10, 2026; all identical compiled and interpreted.

| Kernel | Interpreted | Compiled | Speed-up |
| --- | --- | --- | --- |
| `labels(10000)`: `"p" + string(k) + "_" + string(k * 2)` and its length, per step | 43.2 ms | 10.5 ms | 4× |
| `kinds_loop(10000)`: three calls per step of a function that tests `typeof(x) == "real"` and branches on a kind string | 174 ms | 7.87 ms | 22× |

Building strings is allocation and formatting: each step of `labels` makes five new strings and formats two integers, about 1 µs in all, and that work is the interpreter's own. With `string(k)` and `length(s)` going through `rt_call`, the general route for built-ins, the kernel took 20.2 ms (2×); their own helpers saved about 1 µs per step. Code that only passes strings through and compares them, as option handling does, gains as much as other compiled code: `typeof` is a constant and a comparison is one call.

With the JIT forced on, the tests compile 481 functions (321 after J10), not counting `tests/j11`. Most of the rejections left are function values passed as arguments (`f`, the plot module's callbacks), `global`, matrix literals with vector entries (`[x, y]` of columns), `nothing` as a default (`label = nothing`), `try`, and calls through an expression.

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
