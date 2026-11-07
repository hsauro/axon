# Axon

Axon is a scientific programming language; this repository is its interpreter, written in Delphi.

## Documents

The design lives in `doc/`. The Language Reference is the authority on behaviour; where the milestone plan and the reference disagree, the reference wins.

- `doc/Axon-White-Paper.md`: rationale and examples
- `doc/Axon-Language-Reference.md`: exact syntax and semantics
- `doc/Axon-Milestones.md`: build order (M0–M13) and what each milestone's tests must cover

## Build and test

- `build.cmd` builds Win64 Debug (`build Release` builds Release) with RAD Studio 37.0. Output goes to `Win64\<Config>\axon.exe`.
- `test.cmd` runs every test; `test.cmd -v tests\m03` runs one milestone and lists passes as well.
- From PowerShell, give the scripts by full path, because `cmd /c` does not search the PowerShell location: `cmd /c "$PWD\build.cmd"`, then `cmd /c "$PWD\test.cmd"`.
- macOS builds go through PAServer from the IDE. The POSIX code in `Axon.Platform` can be syntax-checked locally with `dccosxarm64` / `dccosx64`.

## Layout

- `axon.dpr`, `axon.dproj`: console program
- `src/Axon.Cli.pas`: command line (`axon file.sci`, `--tokens`, `--ast`, `test`)
- `src/Axon.Errors.pas`: `EAxonError` with error kinds, and the process exit codes
- `src/Axon.Platform.pas`: the only place for `{$IFDEF MSWINDOWS}`/`POSIX` code, apart from `src/native`
- `src/Axon.TestRunner.pas`: `axon test`
- `src/Axon.Lexer.pas`, `Axon.Parser.pas`, `Axon.Ast.pas`, `Axon.AstDump.pas`: the front end
- `src/Axon.Values.pas`: `TAxValue`, a tagged record holding scalars inline and other payloads in reference-counted objects; also the display forms
- `src/Axon.Ops.pas`: operators, promotion, checked integer arithmetic. Array and range operands are passed on to `Axon.Arrays`.
- `src/Axon.Arrays.pas`: dense arrays. `TArrayObj` (declared in `Axon.Values`) is column-major, with one typed buffer per element type. This unit holds literals, broadcasting, `MatMul`, transpose, index resolution and reductions. Elementwise operations call the scalar operators per element.
- Assignment to `a[i].f[j] = v` and similar goes through `AssignPath`/`SetIn`. `SetIn` walks the path, calling `MakeUnique` on each level before writing; that function copies one level of a list, record or dictionary when it is shared. Arrays at the leaf go to `AssignArraySlot`.
- Copy-on-write: `AssignArraySlot` clones an array when `RefCount > 1`. Never keep an extra `TAxValue` copy of the target array alive while deciding, or every write will copy. `__copies()` counts clones for tests.
- `src/Axon.Complex.pas`: complex arithmetic and principal-value functions
- `src/Axon.Builtins.pas`: prelude functions
- `src/Axon.Interp.pas`: tree-walking evaluator and scopes. Constructs from later milestones raise `ENotImplemented` (exit code 2).
  - Scopes are reference-counted by hand (`AddRef`/`Release`), because closures keep their defining scope alive.
  - Variables are `TVarCell`s, which carry the type annotation and the `global` marker.
  - A function stored in the scope it closes over forms a cycle that is never freed. That's accepted for now.
- `src/Axon.Repl.pas`: the basic REPL (`axon` with no arguments)
- `src/Axon.Packages.pas`: reads `package.toml` (a TOML subset, cached per directory) and resolves module files. `Axon.Interp` loads modules (`LoadModule`, `ExecImport`). Each `TModuleObj` has its own module-root scope, and functions remember their file, so calls switch `FFile`/`FCurrentPath` for error reports and nested imports.
- `src/Axon.Ffi.pas`: `extern`. Calls go through `System.Rtti.Invoke` (no libffi), with argument and result conversion and `ref`/`ptr`/`cstring` handling. Callback errors are held as pending and raised after the native call returns.
- `src/native/Axon.Native.Callbacks.pas` and the generated `Axon.Native.Trampolines.pas`: a fixed pool of callback trampolines (32 per return kind). Regenerate the trampolines with `bash tools/gen_trampolines.sh`; never edit them by hand. Win64 uses inline-assembly stubs that spill the registers into the caller's home area; macOS uses Pascal functions taking 8 integers and 8 doubles.
- `tests/m09/native/axontest.dpr`: the native test library, written in Delphi. `build.cmd` builds it into `tests/m09/bin` (gitignored).
- `src/Axon.Linalg.pas`: the core `\`, `/` and matrix `^`, and the BLAS product behind `*`, through `src/native/Axon.Native.Blas.pas` and `Axon.Native.Lapack.pas`. Those units load OpenBLAS on first use, so the interpreter still starts without it.
- `src/Axon.Sparse.pas`: sparse matrices (`TSparseObj`, CSC, declared in `Axon.Values`). Values are always stored as `TComplex` with an `IsComplex` flag. Holds construction from triplets, sparse arithmetic, the dispatch for operators with a sparse operand (`Axon.Ops` checks for sparse before arrays) and `S \ b`. Indexing and assignment are in `Axon.Interp` (`IndexSparse`, `AssignSparseSlot`); overwriting an existing entry is done in place after copy-on-write, anything else rebuilds the matrix.
- `src/Axon.SparseLU.pas`: the sparse LU, written in Delphi so that no SuiteSparse library is needed: minimum-degree ordering on A + A' (degree buckets), then left-looking Gilbert–Peierls factorisation with threshold partial pivoting that prefers the diagonal.
- `stdlib/`: the standard library, written in Axon. `linalg.sci` binds LAPACKE through `extern "libopenblas"`. A post-build step copies `stdlib/*.sci` to `Win64\<Config>\stdlib`.
- Numerical tests compare against reference values with the helpers in `tests/m10/testing.sci` (`approx`, `approx_set`, `orthonormal`), not with exact printed digits.
- Module tests: `tests/m08` holds fixture modules next to the tests. A `stdlib/` folder inside a milestone folder becomes `AXON_STDLIB` for that folder's tests.
- `src/native/Axon.Native.*.pas`: one unit per C library. Declarations are added in the milestone that first uses the library.
- `lib/win64/`: shipped DLLs (OpenBLAS with its MinGW runtime, SUNDIALS CVODE). A post-build step in `axon.dproj` copies them next to `axon.exe`. See `lib/README.md` for where they came from.
- `tests/mNN/`: tests for milestone NN

## Conventions

- An uncaught error prints `Kind: message` on the first line of stderr, followed by trace lines (`  at file:line:col in function`, innermost first), and exits with code 1. The test runner relies on that first line.
- Traces are built as an error propagates: `EAxonError.Locate` records the innermost position in the current frame, and `LeaveFunction` (called in `Invoke` as an error leaves a body) names and closes the frame. An error raised with a node position should use `CreateAt`; errors without one are located by the enclosing call or statement.
- Exit codes: 0 ok, 1 uncaught Axon error, 2 usage or unimplemented feature, 3 internal error.
- Tests: `name.sci` plus `name.out`, `name.tokens` or `name.ast`; or a first line `#! error: Kind`, with an optional `name.err` that stderr must match exactly. Only `.sci` files directly in `tests/mNN/` are tests; subfolders hold fixtures.
- Write expected files (`.out`, `.tokens`, `.err`) from the reference by hand, not by recording the interpreter's output, so a test can catch a real bug.
- `--tokens` prints one token per line as `LINE:COL KIND [VALUE]`. The kinds are EOF, NEWLINE, IDENT, INT (decimal value), REAL and IMAG (literal without `_`), STRING and DOCSTRING (quoted and re-escaped), KEYWORD and OP. See `src/Axon.Tokens.pas`.
- `--ast` prints S-expressions, one statement per line, with block bodies on indented lines. The full format is in the header of `src/Axon.AstDump.pas`.
- Debug builds have range and overflow checking on. `Axon.Ops` turns overflow checking off (`{$Q-}`) because it detects integer overflow explicitly and raises `OverflowError`.
- Floating-point exceptions are masked at start-up (`SetExceptionMask`), so real arithmetic follows IEEE 754 (Inf and NaN) instead of raising Delphi exceptions.
- For elementary functions whose last printed digit can differ between platforms' math libraries, tests check identities against a tolerance instead of printing 15 digits.
- Source files are UTF-8 without a byte-order mark, which Delphi reads as ANSI, so a non-ASCII character inside a string literal gets mangled. Write it as a character code instead (`#$00D7` for ×). Non-ASCII in comments is fine.
- Delphi `{ … }` comments don't nest, so a comment that contains `{` or `}` (grammar excerpts, `matrix{T}`) must use `(* … *)`.
- Parser ownership: a function that takes a child node frees it if it fails, so the caller must clear its own reference before the call. See `ParsePostfix`.
