# Native libraries

Prebuilt native libraries shipped with Axon. A Win64 build (from the IDE or `build.cmd`) copies `lib/win64/*.dll` next to `axon.exe` as a post-build step.

## Win64

| File | Library | Needed by | Source |
| --- | --- | --- | --- |
| `libopenblas.dll` | OpenBLAS (BLAS, LAPACK, LAPACKE), MinGW build | M10 `*` and `linalg` | `CommonCode/LAPACKE/Win64/Debug` |
| `libgfortran-3.dll`, `libgcc_s_seh-1.dll`, `libquadmath-0.dll` | MinGW runtime for OpenBLAS | `libopenblas.dll` | same |
| `sundials_cvode.dll` | SUNDIALS CVODE 7.5 (Sept 2025), 64-bit release | M13 `ode` BDF | `CommonCode/SunDials Suite/CVODE7_5_Delphi/Win64/Debug` |
| `sundials_core.dll`, `sundials_nvecserial.dll`, `sundials_sunmatrixdense.dll`, `sundials_sunlinsoldense.dll` | SUNDIALS support libraries for CVODE | `sundials_cvode.dll` | same |
| `sk4d.dll` | Skia (Skia4Delphi build), as shipped with RAD Studio 13 | M13 `graphics` and `plot` | `Studio\37.0\bin64\sk4d.dll` |
| `mir.dll` | MIR v1.0.0 (`mir.c`, `mir-gen.c`) plus Axon's shim `src/native/axmir.c`; MSVC 2022, static C runtime | L2 JIT (`axon --jit-selftest`) | Built by `tools/build_mir.cmd` from github.com/vnmakarov/mir |

- **MSVC runtime.** The SUNDIALS DLLs were built with MSVC and need `VCRUNTIME140.dll` (the Visual C++ 2015–2022 redistributable) on the machine.
- **Left out.** `sundials_sunlinsolband.dll` is not shipped, because it needs `sundials_sunmatrixband.dll`, which isn't in the source folder.
- **OpenBLAS version.** The DLL carries no version string. It exports `dgemm_`, `zgemm_`, `dgesv_` and `LAPACKE_*`.
- **Skia.** `sk4d.dll` (about 21 MB) loads at the first `graphics` call, not at start-up, so `axon` runs without it until something is drawn. It is a redistributable file of RAD Studio. On macOS Skia is linked statically into `axon` (`libsk4d.a`), so nothing is shipped.
- **MIR.** `mir.dll` loads on first use, like OpenBLAS, and needs no other DLL. Rebuild it with `tools\build_mir.cmd` after changing `axmir.c`.
- **Licences.** OpenBLAS, SUNDIALS and Skia are BSD-3-Clause; MIR is MIT. The MinGW runtime DLLs are GPL with the GCC Runtime Library Exception. Add the licence texts here before a public release.

Delphi bindings for these libraries already exist in `CommonCode/LAPACKE` and `CommonCode/SunDials Suite`, and serve as references. Axon calls CVODE from Axon code through `extern` (M13), so only the interpreter's own native calls (such as `dgemm` for `*`) need Delphi declarations, in `src/native`.

## macOS (arm64)

Dylibs in `lib/macos/` are deployed next to `axon` in the IDE's app bundle (`tools/gen_mac_deploy.py` lists them in `ide/AxonIDE.dproj`; rerun it after adding one). `axon` loads them from its own folder first, for its own calls and for `extern` alike.

| File | Library | Needed by | Source |
| --- | --- | --- | --- |
| `libopenblas.dylib` | OpenBLAS 0.3.28 (BLAS, LAPACK, LAPACKE), `TARGET=VORTEX`, built without Fortran (`NOFORTRAN=1 C_LAPACK=1`) | `*` and `linalg` | Built on the Mac by `tools/build_openblas_mac.sh` |
| `libsundials_core.dylib`, `libsundials_cvode.dylib` | SUNDIALS CVODE 7.5.0, arm64 (the vector, dense matrix and dense solver are inside `libsundials_cvode`) | `ode.solve(..., method = "bdf")` | `libsundials_core.7.dylib` and `libsundials_cvode.7.dylib` from `RoadRunner_Delphi_JIT/OSXARM64/Debug`, renamed |
| `libmir.dylib` | MIR v1.0.0 (`mir.c`, `mir-gen.c`) plus Axon's shim `src/native/axmir.c`, clang `-O2` | The JIT | Built on the Mac by `tools/build_mir_mac.sh` (with `axmir.c` copied next to it) |

- **No Fortran runtime.** OpenBLAS's C translation of LAPACK means the dylib depends only on system libraries (`otool -L` shows `libSystem`), unlike Homebrew's build, which needs gfortran's runtime dylibs.
- **Why not Accelerate.** Apple's framework has BLAS and Fortran-style LAPACK but no LAPACKE, which both `Axon.Native.Lapack` and `stdlib/linalg.sci` call.
- **CVODE install names.** These builds name themselves, and `libsundials_cvode` names its dependency, by absolute paths from the machine that built them (`/Users/hsauro/sundials-install/lib/libsundials_core.7.dylib`). `Axon.Native.Cvode` loads `libsundials_core` from the bundle before `libsundials_cvode`, so that dependency resolves to the copy already loaded: checked on the Mac with `~/sundials-install` renamed away, the bundle's copies are used. Rewriting the names to `@loader_path/…` (`install_name_tool`, then signing again) would make that independent of the load order.
- **MIR.** Rebuild `libmir.dylib` with `tools/build_mir_mac.sh` after changing `axmir.c`, as `mir.dll` with `tools/build_mir.cmd` on Windows.
