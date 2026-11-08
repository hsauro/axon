#!/bin/bash
# Builds libopenblas.dylib for Apple Silicon (arm64), for Axon on macOS.
#
# Run on the Mac (needs the Xcode command line tools: xcode-select --install):
#
#     bash build_openblas_mac.sh
#
# (or type "bash " in Terminal and drag this file into the window).
#
# It downloads the OpenBLAS release source, builds it without Fortran
# (NOFORTRAN=1 C_LAPACK=1: LAPACK comes from OpenBLAS's C translation, and
# LAPACKE is built as usual), so the dylib depends only on macOS's own
# libraries and no gfortran runtime has to be shipped. The result,
# ./libopenblas.dylib, goes into lib/macos/ in the Axon repository; the IDE's
# deployment puts it next to axon in the app bundle.
set -euo pipefail

VERSION=0.3.28
TARGET=VORTEX          # Apple M1 and later
WORK="${TMPDIR:-/tmp}/axon-openblas"
# The result goes next to this script, wherever it is run from (so it can be
# started by typing "bash " and dragging the script into Terminal).
OUT="$(cd "$(dirname "$0")" && pwd)/libopenblas.dylib"

# Everything is built in $WORK, in the user's temporary folder, and $WORK is
# deleted when the script ends (also after an error): the only file left
# behind is libopenblas.dylib next to this script. Nothing is installed.
trap 'cd /; rm -rf "$WORK"' EXIT
mkdir -p "$WORK"
cd "$WORK"
if [ ! -d "OpenBLAS-$VERSION" ]; then
  curl -L -o "OpenBLAS-$VERSION.tar.gz" \
    "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$VERSION/OpenBLAS-$VERSION.tar.gz"
  tar xzf "OpenBLAS-$VERSION.tar.gz"
fi
cd "OpenBLAS-$VERSION"

make -j"$(sysctl -n hw.ncpu)" TARGET=$TARGET NOFORTRAN=1 C_LAPACK=1 \
  USE_OPENMP=0 NUM_THREADS=32 DYNAMIC_ARCH=0 libs shared

# The shared library is libopenblas_<target>p-r<version>.dylib (libopenblas.dylib
# links to it). Copy the real file, name it for loading from the app bundle,
# and sign it again: changing the install name invalidates the signature, and
# Apple Silicon refuses to load unsigned code.
cp -L libopenblas.dylib "$OUT"
install_name_tool -id @rpath/libopenblas.dylib "$OUT"
codesign --force --sign - "$OUT"

echo
echo "Built $OUT"
echo "Dependencies (only system libraries expected):"
otool -L "$OUT"
echo "Symbols Axon needs:"
for s in _dgemm_ _zgemm_ _LAPACKE_dgetrf _LAPACKE_dgesv _LAPACKE_dgeev _LAPACKE_zgelsd; do
  if nm -gU "$OUT" | grep -q " $s\$"; then echo "  $s ok"; else echo "  $s MISSING"; fi
done
