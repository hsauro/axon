# Native libraries

Prebuilt native libraries shipped with Axon. A Win64 build (from the IDE or `build.cmd`) copies `lib/win64/*.dll` next to `axon.exe` as a post-build step.

## Win64

| File | Library | Needed by | Source |
| --- | --- | --- | --- |
| `libopenblas.dll` | OpenBLAS (BLAS, LAPACK, LAPACKE), MinGW build | M10 `*` and `linalg` | `CommonCode/LAPACKE/Win64/Debug` |
| `libgfortran-3.dll`, `libgcc_s_seh-1.dll`, `libquadmath-0.dll` | MinGW runtime for OpenBLAS | `libopenblas.dll` | same |
| `sundials_cvode.dll` | SUNDIALS CVODE 7.5 (Sept 2025), 64-bit release | M13 `ode` BDF | `CommonCode/SunDials Suite/CVODE7_5_Delphi/Win64/Debug` |
| `sundials_core.dll`, `sundials_nvecserial.dll`, `sundials_sunmatrixdense.dll`, `sundials_sunlinsoldense.dll` | SUNDIALS support libraries for CVODE | `sundials_cvode.dll` | same |

- **MSVC runtime.** The SUNDIALS DLLs were built with MSVC and need `VCRUNTIME140.dll` (the Visual C++ 2015–2022 redistributable) on the machine.
- **Left out.** `sundials_sunlinsolband.dll` is not shipped, because it needs `sundials_sunmatrixband.dll`, which isn't in the source folder.
- **OpenBLAS version.** The DLL carries no version string. It exports `dgemm_`, `zgemm_`, `dgesv_` and `LAPACKE_*`.
- **Licences.** OpenBLAS and SUNDIALS are BSD-3-Clause. The MinGW runtime DLLs are GPL with the GCC Runtime Library Exception. Add the licence texts here before a public release.

Delphi bindings for these libraries already exist in `CommonCode/LAPACKE` and `CommonCode/SunDials Suite`, and serve as references. Axon calls CVODE from Axon code through `extern` (M13), so only the interpreter's own native calls (such as `dgemm` for `*`) need Delphi declarations, in `src/native`.

## macOS

No dylibs are shipped yet. A CVODE arm64 set already exists in `RoadRunner_Delphi_JIT/OSXARM64/Debug`. On macOS, Apple's Accelerate framework can provide BLAS and LAPACK.
