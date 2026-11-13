# Native libraries

Prebuilt native libraries shipped with Axon. A Win64 build (from the IDE or `build.cmd`) copies `lib/win64/*.dll` next to `axon.exe` as a post-build step.

## Win64

| File | Library | Needed by | Source |
| --- | --- | --- | --- |
| `libopenblas.dll` | OpenBLAS 0.3.34 (BLAS, LAPACK, LAPACKE), 32-bit integers, `DYNAMIC_ARCH` | `*`, `\` and `linalg` | `bin/libopenblas.dll` from `OpenBLAS-0.3.34-x64.zip`, the official release on github.com/OpenMathLib/OpenBLAS (SHA-256 of the zip `e9cb6134541f36c27346d5fc5995652f060fba227cebbbabcbda5a5a44d7c76b`) |
| `sundials_cvode.dll` | SUNDIALS CVODE 7.5 (Sept 2025), 64-bit release | M13 `ode` BDF | `CommonCode/SunDials Suite/CVODE7_5_Delphi/Win64/Debug` |
| `sundials_kinsol.dll` | SUNDIALS KINSOL 7.5 (Sept 2025), 64-bit release; holds its own serial vector, dense matrix and dense solver, and needs only `sundials_core.dll` (a separate build of the same version, which it loads without trouble) | `nonlin.solve`, `antimony.steady_state` | `CommonCode/SunDials Suite/KinSol_7_5_Delphi/Win64/Debug` (SHA-256 `1a4ca99c9394968e5127595d2e701cf661c3fa57153edf034b0c14e55cf87c8d`) |
| `sundials_core.dll`, `sundials_nvecserial.dll`, `sundials_sunmatrixdense.dll`, `sundials_sunlinsoldense.dll` | SUNDIALS support libraries for CVODE | `sundials_cvode.dll` | same |
| `sk4d.dll` | Skia (Skia4Delphi build), as shipped with RAD Studio 13 | M13 `graphics` and `plot` | `Studio\37.0\bin64\sk4d.dll` |
| `mir.dll` | MIR master at commit `dc2c763` (2026-10, after v1.0.0; `mir.c`, `mir-gen.c`) plus Axon's shim `src/native/axmir.c`; MSVC 2022, static C runtime | L2 JIT (`axon --jit-selftest`) | Built by `tools/build_mir.cmd` from github.com/vnmakarov/mir |

- **MSVC runtime.** The SUNDIALS DLLs were built with MSVC and need `VCRUNTIME140.dll` (the Visual C++ 2015–2022 redistributable) on the machine.
- **Left out.** `sundials_sunlinsolband.dll` is not shipped, because it needs `sundials_sunmatrixband.dll`, which isn't in the source folder.
- **OpenBLAS.** The release DLL needs only `KERNEL32.dll` and `msvcrt.dll`, so no MinGW runtime is shipped. `openblas_get_config()` reports the version and the kernels chosen for the processor (`OpenBLAS 0.3.34 DYNAMIC_ARCH NO_AFFINITY SkylakeX`). Use the `x64` zip, not `x64-64`, whose functions take 64-bit integers. The DLL it replaced, an older MinGW build, did not recognise current processors and fell back to its Prescott (SSE3) kernels: the 500×500 product took 2.9 ms, against 1.5 ms now.
- **OpenBLAS threads.** OpenBLAS starts one thread per logical CPU, but its LAPACK factorisations slow down with many threads (on a 10-core i9-9900X, LU of a 500×500 matrix took 47 ms on 20 threads and 6 ms on 4). `ConfigureOpenBlas` in `src/native/Axon.Native.Blas.pas` therefore caps it at 4 when the library loads, unless `OPENBLAS_NUM_THREADS` or `OMP_NUM_THREADS` is set; `linalg.set_threads` changes it.
- **Skia.** `sk4d.dll` (about 21 MB) loads at the first `graphics` call, not at start-up, so `axon` runs without it until something is drawn. It is a redistributable file of RAD Studio. On macOS Skia is linked statically into `axon` (`libsk4d.a`), so nothing is shipped.
- **MIR.** `mir.dll` loads on first use, like OpenBLAS, and needs no other DLL. Rebuild it with `tools\build_mir.cmd` after changing `axmir.c`. It is pinned to a commit after v1.0.0 because v1.0.0's optimiser (level 2, which the JIT uses) compiled some large functions wrongly: the 68 rate laws of an E. coli model gave two wrong rates when compiled (`tests/m13/antimony_ecoli.sci` checks them). `AXON_MIR_OPT=0`..`3` sets the optimisation level, to tell an optimiser bug from a code-generation one.
- **Licences.** OpenBLAS, SUNDIALS and Skia are BSD-3-Clause; MIR is MIT. Add the licence texts here before a public release.

Delphi bindings for these libraries already exist in `CommonCode/LAPACKE` and `CommonCode/SunDials Suite`, and serve as references. The interpreter calls CVODE and KINSOL from Delphi (`src/native/Axon.Native.Cvode.pas`, `Axon.Native.Kinsol.pas`), declaring only the functions it uses.

## macOS (arm64)

Dylibs in `lib/macos/` are deployed next to `axon` in the IDE's app bundle (`tools/gen_mac_deploy.py` lists them in `ide/AxonIDE.dproj`; rerun it after adding one). `axon` loads them from its own folder first, for its own calls and for `extern` alike.

| File | Library | Needed by | Source |
| --- | --- | --- | --- |
| `libopenblas.dylib` | OpenBLAS 0.3.28 (BLAS, LAPACK, LAPACKE), `TARGET=VORTEX`, built without Fortran (`NOFORTRAN=1 C_LAPACK=1`) | `*` and `linalg` | Built on the Mac by `tools/build_openblas_mac.sh` |
| `libsundials_core.dylib`, `libsundials_cvode.dylib` | SUNDIALS CVODE 7.5.0, arm64 (the vector, dense matrix and dense solver are inside `libsundials_cvode`) | `ode.solve(..., method = "bdf")` | `libsundials_core.7.dylib` and `libsundials_cvode.7.dylib` from `RoadRunner_Delphi_JIT/OSXARM64/Debug`, renamed |
| `libsundials_kinsol.dylib` | SUNDIALS KINSOL 7.5.0, arm64 (**not yet added**: copy `libsundials_kinsol.7.dylib` from the Mac's SUNDIALS install, `~/sundials-install/lib`, renamed, then rerun `tools/gen_mac_deploy.py`) | `nonlin.solve`, `antimony.steady_state` | the same SUNDIALS build as CVODE |
| `libmir.dylib` | MIR master at commit `dc2c763` (as `mir.dll`; `mir.c`, `mir-gen.c`) plus Axon's shim `src/native/axmir.c`, clang `-O2` | The JIT | Built on the Mac by `tools/build_mir_mac.sh` (with `axmir.c` copied next to it) |

- **No Fortran runtime.** OpenBLAS's C translation of LAPACK means the dylib depends only on system libraries (`otool -L` shows `libSystem`), unlike Homebrew's build, which needs gfortran's runtime dylibs.
- **Why not Accelerate.** Apple's framework has BLAS and Fortran-style LAPACK but no LAPACKE, which both `Axon.Native.Lapack` and `stdlib/linalg.sci` call.
- **CVODE install names.** These builds name themselves, and `libsundials_cvode` names its dependency, by absolute paths from the machine that built them (`/Users/hsauro/sundials-install/lib/libsundials_core.7.dylib`). `Axon.Native.Cvode` loads `libsundials_core` from the bundle before `libsundials_cvode`, so that dependency resolves to the copy already loaded: checked on the Mac with `~/sundials-install` renamed away, the bundle's copies are used. Rewriting the names to `@loader_path/…` (`install_name_tool`, then signing again) would make that independent of the load order.
- **MIR.** Rebuild `libmir.dylib` with `tools/build_mir_mac.sh` after changing `axmir.c`, as `mir.dll` with `tools/build_mir.cmd` on Windows.
