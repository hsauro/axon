# Licences of the native libraries

The prebuilt libraries in `lib/win64` and `lib/macos` are third-party
software. Their licences require the copyright notices below to accompany
copies of the binaries. Each text is copied unchanged from the project's
official repository, at the version Axon ships where the project tags its
releases.

| File | Library | Licence | Source of the text |
| --- | --- | --- | --- |
| [OpenBLAS-LICENSE.txt](OpenBLAS-LICENSE.txt) | OpenBLAS 0.3.34 (`libopenblas.dll`, `libopenblas.dylib`) | BSD-3-Clause | `LICENSE` at tag `v0.3.34` of github.com/OpenMathLib/OpenBLAS |
| [SUNDIALS-LICENSE.txt](SUNDIALS-LICENSE.txt), [SUNDIALS-NOTICE.txt](SUNDIALS-NOTICE.txt) | SUNDIALS 7.5 (CVODE, KINSOL and their support libraries) | BSD-3-Clause, with a U.S. Department of Energy notice | `LICENSE` and `NOTICE` at tag `v7.5.0` of github.com/LLNL/sundials |
| [Skia-LICENSE.txt](Skia-LICENSE.txt) | Skia (`sk4d.dll` on Windows; linked into `axon` on macOS) | BSD-3-Clause | `LICENSE` on the `main` branch of github.com/google/skia |
| [MIR-LICENSE.txt](MIR-LICENSE.txt) | MIR at commit `dc2c763` (`mir.dll`, `libmir.dylib`) | MIT | `LICENSE` at that commit of github.com/vnmakarov/mir |

**The GCC runtime inside OpenBLAS.** The official Windows build of OpenBLAS
is compiled with MinGW-w64 GCC and contains parts of the GCC runtime
libraries (from `libgfortran`, linked statically). These parts are licensed
under the GNU GPL version 3 with the GCC Runtime Library Exception. The
exception allows software compiled with GCC to include them and to be
distributed under any licence, so they do not bring the GPL to OpenBLAS or
to Axon. No separate GCC runtime DLLs are shipped.

**`sk4d.dll`.** The Windows DLL is the Skia4Delphi build that RAD Studio 13
ships as a redistributable file; Skia itself is under the licence above.

Axon's own code is under the MIT licence in the repository's top-level
[LICENSE](../../LICENSE).
