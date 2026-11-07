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
- `src/native/Axon.Native.*.pas`: one unit per C library. Declarations are added in the milestone that first uses the library.
- `lib/win64/`: shipped DLLs (OpenBLAS with its MinGW runtime, SUNDIALS CVODE). A post-build step in `axon.dproj` copies them next to `axon.exe`. See `lib/README.md` for where they came from and what's missing (libffi, KLU).
- `tests/mNN/`: tests for milestone NN

## Conventions

- An uncaught error prints `Kind: message` on the first line of stderr, followed by trace lines, and exits with code 1. The test runner relies on that first line.
- Exit codes: 0 ok, 1 uncaught Axon error, 2 usage or unimplemented feature, 3 internal error.
- Tests: `name.sci` plus `name.out`, `name.tokens` or `name.ast`; or a first line `#! error: Kind`, with an optional `name.err` that stderr must match exactly. Only `.sci` files directly in `tests/mNN/` are tests; subfolders hold fixtures.
- Write expected files (`.out`, `.tokens`, `.err`) from the reference by hand, not by recording the interpreter's output, so a test can catch a real bug.
- `--tokens` prints one token per line as `LINE:COL KIND [VALUE]`. The kinds are EOF, NEWLINE, IDENT, INT (decimal value), REAL and IMAG (literal without `_`), STRING and DOCSTRING (quoted and re-escaped), KEYWORD and OP. See `src/Axon.Tokens.pas`.
- `--ast` prints S-expressions, one statement per line, with block bodies on indented lines. The full format is in the header of `src/Axon.AstDump.pas`.
- Debug builds have range and overflow checking on.
- Delphi `{ … }` comments don't nest, so a comment that contains `{` or `}` (grammar excerpts, `matrix{T}`) must use `(* … *)`.
- Parser ownership: a function that takes a child node frees it if it fails, so the caller must clear its own reference before the call. See `ParsePostfix`.
