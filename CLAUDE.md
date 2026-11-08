# Axon

Axon is a scientific programming language; this repository is its interpreter, written in Delphi.

## Documents

The design lives in `doc/`. The Language Reference is the authority on behaviour; where the milestone plan and the reference disagree, the reference wins.

- `doc/Axon-White-Paper.md`: rationale and examples
- `doc/Axon-Language-Reference.md`: exact syntax and semantics
- `doc/Axon-Milestones.md`: build order (M0–M13) and what each milestone's tests must cover
- `doc/Axon-JIT-Plan.md`: the L2 MIR JIT plan (decisions D1–D7, milestones J0–J8)

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
- `src/Axon.Repl.pas`: the REPL (`axon` with no arguments; prompts `> ` and `... `), and `axon --transcript file`, which replays the `> `/`... ` lines of a transcript and writes the session, errors included, to stdout.
- `src/Axon.Help.pas`: the REPL's `help name`. Function headers come from the source text (`ParseSource` in `Axon.Parser` stores `TFunctionDecl.Header` for top-level functions); built-ins are described by a table in this unit, so add a row when adding a built-in. A `##` block that opens a file and is followed by a blank line is the module docstring (`TProgram.Doc`).
- `src/Axon.Packages.pas`: reads `package.toml` (a TOML subset, cached per directory) and resolves module files. `Axon.Interp` loads modules (`LoadModule`, `ExecImport`). Each `TModuleObj` has its own module-root scope, and functions remember their file, so calls switch `FFile`/`FCurrentPath` for error reports and nested imports.
- `src/Axon.Ffi.pas`: `extern`. Calls go through `System.Rtti.Invoke` (no libffi), with argument and result conversion and `ref`/`ptr`/`cstring` handling. Callback errors are held as pending and raised after the native call returns.
- `src/native/Axon.Native.Callbacks.pas` and the generated `Axon.Native.Trampolines.pas`: a fixed pool of callback trampolines (32 per return kind). Regenerate the trampolines with `bash tools/gen_trampolines.sh`; never edit them by hand. Win64 uses inline-assembly stubs that spill the registers into the caller's home area; macOS uses Pascal functions taking 8 integers and 8 doubles.
- `tests/m09/native/axontest.dpr`: the native test library, written in Delphi. `build.cmd` builds it into `tests/m09/bin` (gitignored).
- `src/Axon.Linalg.pas`: the core `\`, `/` and matrix `^`, and the BLAS product behind `*`, through `src/native/Axon.Native.Blas.pas` and `Axon.Native.Lapack.pas`. Those units load OpenBLAS on first use, so the interpreter still starts without it.
- `src/Axon.Sparse.pas`: sparse matrices (`TSparseObj`, CSC, declared in `Axon.Values`). Values are always stored as `TComplex` with an `IsComplex` flag. Holds construction from triplets, sparse arithmetic, the dispatch for operators with a sparse operand (`Axon.Ops` checks for sparse before arrays) and `S \ b`. Indexing and assignment are in `Axon.Interp` (`IndexSparse`, `AssignSparseSlot`); overwriting an existing entry is done in place after copy-on-write, anything else rebuilds the matrix.
- `src/Axon.SparseLU.pas`: the sparse LU, written in Delphi so that no SuiteSparse library is needed: minimum-degree ordering on A + A' (degree buckets), then left-looking Gilbert–Peierls factorisation with threshold partial pivoting that prefers the diagonal.
- `src/Axon.NativeModules.pas`: core modules written in Delphi. `import m` uses one when no `m.sci` is found; `Axon.IoModule` (`io`) and `Axon.Graphics` (`graphics`) register themselves in their `initialization` sections. Add help rows for their functions to the table in `Axon.Help`.
- `src/Axon.TimeModule.pas`: the core module `time` (`clock`, `now`, `sleep`, `elapsed`, `bench`, `format`). `elapsed` and `bench` call Axon functions through `CallAxon` in `Axon.NativeModules`, a hook the interpreter sets to its `CallValue` when it is created (one interpreter per process).
- `src/Axon.Graphics.pas`: renders a scene (an Axon record of drawing items) to PNG, SVG or PDF through Skia's flat C API (`System.Skia.API`). Don't use the high-level `System.Skia` unit: its class constructor loads `sk4d.dll` at start-up and aborts if it is missing. Here `SkInitialize` runs at the first call. On macOS Skia is linked statically.
- `stdlib/ode.sci`: RK45 in Axon, and BDF through CVODE (`extern`). CVODE keeps its callbacks, so two module functions are kept once (`keep`) and dispatch to the module variable `current`; a solve saves and restores it. CVODE's vectors are copied with `memcpy` from `libc`, which `stdlib/package.toml` maps per platform.
- `stdlib/plot.sci`: figures built in Axon and drawn through `graphics`.
- `stdlib/`: the standard library, written in Axon. `linalg.sci` binds LAPACKE through `extern "libopenblas"`. A post-build step copies `stdlib/*.sci` and `stdlib/package.toml` to `Win64\<Config>\stdlib`.
- Tests that write files name them `_tmp_*` (gitignored) and delete them. A milestone test file must not share a name with a module it imports (`io.sci` would shadow `io`).
- Numerical tests compare against reference values with the helpers in `tests/m10/testing.sci` (`approx`, `approx_set`, `orthonormal`), not with exact printed digits.
- Module tests: `tests/m08` holds fixture modules next to the tests. A `stdlib/` folder inside a milestone folder becomes `AXON_STDLIB` for that folder's tests.
- `src/native/Axon.Native.*.pas`: one unit per C library. Declarations are added in the milestone that first uses the library.
- `src/native/Axon.Native.Mir.pas` and `src/native/axmir.c`: the MIR JIT library (L2, `doc/Axon-JIT-Plan.md`). `mir.dll` is MIR's `mir.c` and `mir-gen.c` plus the shim `axmir.c`, built by `tools\build_mir.cmd` (clones MIR v1.0.0 into the gitignored `third_party/mir`, builds with MSVC 2022 through `tools/mir/CMakeLists.txt`, copies to `lib/win64`). Delphi calls MIR's pointer/integer functions directly; operands go through the shim as `TAxMirOp`, because `MIR_op_t`'s bitfield layout differs between compilers; instruction codes are looked up by name (`MirCode`). Loaded on first use (`MirAvailable`). `axon --jit-selftest` (`src/Axon.JitSelfTest.pas`) checks the library.
- `bench/`: JIT benchmark kernels (annotated functions timed with `time.bench`); `bench.cmd [Debug]` runs them with `Win64\Release\axon.exe` by default. Baselines are recorded in `doc/Axon-JIT-Plan.md`.
- `lib/win64/`: shipped DLLs (OpenBLAS with its MinGW runtime, SUNDIALS CVODE). A post-build step in `axon.dproj` copies them next to `axon.exe`. See `lib/README.md` for where they came from.
- `ide/`: the Axon IDE (FMX, Win64 and macOS ARM64), `AxonIDE.dproj`. It builds into `Win64\<Config>` next to `axon.exe` and runs programs as a separate `axon` process in the file's directory (`uProcessRunner`: pipes read on threads, UTF-8 decoded, delivered with `TThread.Queue`; Stop kills the process). The editor is `TSkiaCodeEditor` from `..\RhodyComponents\RhoEditor\Source`, referenced in place through the unit search path; `uAxonHighlighter` is its Axon tokenizer (nested `#= =#` comments carry their depth in the lex state). `uRunReport` parses error reports so trace lines become links and the error location gets a squiggle marker. The REPL tab drives `axon --repl-protocol` through a stdin pipe (`TProcessRunner.WriteInput`); the protocol's marker lines (#1 then `>` or `.`) set the prompt, and #2-prefixed lines are error reports. Help (F1) on the name under the caret reads a function or record defined in the file from the editor text; anything else goes to a short-lived `axon --repl-protocol` that runs the file's `import`/`from` lines, then `help name` (the answer is the output after the last ready marker before stdin closes). Syntax is checked as you type: 600 ms after the last edit the text is piped to `axon --check -`, and a `SyntaxError` becomes a squiggle marker; a result for text that has changed since is discarded and the check rerun. Figures from `plot.show()`: the IDE sets `AXON_SHOW_DIR` (a temp folder per IDE, deleted on exit) for every `axon` it starts; `graphics.show` writes the PNG there and a line #3`show <path>` to stderr, which the IDE turns into the plot pane image. Without `AXON_SHOW_DIR`, `graphics.show` opens the system viewer (`OpenWithDefaultApp` in `Axon.Platform`); the test runner sets it so tests never open windows. View > Dark Theme switches live: the FMX style `ide/styles/Dark.style` (from RAD Studio's Redist, no platform restriction; our copy uses blue for every orange or gold accent, grey scrollbar thumbs and light grey menu shortcuts; see `AxonIDEStyles.rc`). On Windows the menu is an FMX `TMenuBar` so it follows the style (a native menu cannot be restyled); on macOS it stays the native `TMainMenu` is embedded as RCDATA `DARKSTYLE` through `AxonIDEStyles.rc` and set with `TStyleManager.TrySetStyleFromResource`; editors take dark colours and `DarkAxonColors`, the help viewer `ApplyTheme(rtDark)`, and output/REPL lines are recoloured by role (`TPanePalette`). The choice is `Theme=` in `settings.ini`. Edit > Preferences (Ctrl+,; `uPreferences`, a dialog built in code) sets the editor font size and the output font size (Output, REPL and Help panes; list row heights follow it); applied live and saved under `[Preferences]` in `settings.ini`. `TextToShortCut` cannot parse `Ctrl+,` or `Ctrl+/`, so `AddMenuItem` builds those from key codes, and on Windows `TShortCutLabels` wraps the menu service so they are labelled without quotes. A Welcome tab (not a document; `FWelcomeTab`) shows at start-up without files, from Help > Welcome, and when the last file closes; it lists the recent files and is refreshed with the Open Recent menu. The IDE keeps recent files and its layout (window bounds and maximized state, plot pane width, bottom pane height and tab) in `settings.ini` under `TPath.GetHomePath\AxonIDE`; normal bounds are recorded after a resize settles, because a maximizing resize arrives before `WindowState` changes. `build.cmd` builds the IDE when that folder exists.
- `examples/`: example programs shown on the IDE's welcome screen (title = first `##` line). Copied next to the IDE at build time; the IDE opens a copy in `Documents/Axon Examples` so the originals stay unchanged.
- `help/`: the IDE's markdown help pages, shown in its Documentation tab with `TRhoMarkdownViewer` from `..\RhodyComponents\RhoMarkDownViewer\Source` (referenced in place). The build copies them, plus `doc/Axon-Language-Reference.md` and `doc/Axon-White-Paper.md`, into `Win64\<Config>\help`. Code blocks fenced as `axon` are coloured by `ide/uAxonMarkdown.pas` (the editor's tokenizer). Every `axon` block in `getting-started.md` and `tour.md` should run: extract and run them after editing.
- `tests/mNN/`: tests for milestone NN

## Conventions

- An uncaught error prints `Kind: message` on the first line of stderr, followed by trace lines (`  at file:line:col in function`, innermost first), and exits with code 1. The test runner relies on that first line.
- Traces are built as an error propagates: `EAxonError.Locate` records the innermost position in the current frame, and `LeaveFunction` (called in `Invoke` as an error leaves a body) names and closes the frame. An error raised with a node position should use `CreateAt`; errors without one are located by the enclosing call or statement.
- Exit codes: 0 ok, 1 uncaught Axon error, 2 usage or unimplemented feature, 3 internal error.
- REPL tests are transcripts, `tests/mNN/name.repl`, which `axon --transcript` must reproduce (trailing spaces ignored). Don't put decorative blank lines in them: every non-input line is expected output.
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
