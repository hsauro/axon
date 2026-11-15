#!/bin/bash
# Builds libmir.dylib for Apple Silicon (arm64): the MIR JIT for Axon on macOS.
#
# Copy this script and src/native/axmir.c (Axon's shim over MIR) into one
# folder on the Mac, then in Terminal type "bash " and drag this script into
# the window (needs the Xcode command line tools: xcode-select --install).
#
# It downloads MIR's source at the same commit as tools/build_mir.cmd (master
# after v1.0.0: v1.0.0's optimiser compiled some large functions wrongly) and compiles
# MIR's core (mir.c, mir-gen.c) with the shim into one dylib with clang; no
# CMake or git is needed. The build happens in a temporary folder that is
# deleted at the end; the only file left is libmir.dylib next to this script.
# It goes into lib/macos/ in the Axon repository.
set -euo pipefail

COMMIT=dc2c763f1c8bc746102ce87933d866335f9e6c06
HERE="$(cd "$(dirname "$0")" && pwd)"
SHIM="$HERE/axmir.c"
OUT="$HERE/libmir.dylib"
WORK="${TMPDIR:-/tmp}/axon-mir"

if [ ! -f "$SHIM" ]; then
  echo "axmir.c is missing: copy src/native/axmir.c next to this script." >&2
  exit 1
fi

trap 'cd /; rm -rf "$WORK"' EXIT
mkdir -p "$WORK"
cd "$WORK"
curl -L -o mir.tar.gz "https://github.com/vnmakarov/mir/archive/$COMMIT.tar.gz"
tar xzf mir.tar.gz
SRC="$WORK/mir-$COMMIT"

# The same flags as tools/mir/CMakeLists.txt, optimised as a release build.
# The linker signs the dylib (ad hoc), which Apple Silicon requires.
clang -O2 -DNDEBUG -std=gnu11 -fsigned-char -fPIC -dynamiclib \
  -I"$SRC" "$SRC/mir.c" "$SRC/mir-gen.c" "$SHIM" \
  -install_name @rpath/libmir.dylib -o "$OUT"

echo
echo "Built $OUT"
echo "Dependencies (only system libraries expected):"
otool -L "$OUT"
# The functions src/native/Axon.Native.Mir.pas looks up (macOS adds a
# leading underscore). MIR_init is not among them: since MIR's master after
# v1.0.0 it is a macro over _MIR_init, which only axmir.c calls.
echo "Symbols Axon needs:"
for s in _axmir_op_size _axmir_set_error_handler _axmir_init _axmir_finish \
         _axmir_insn_code _axmir_new_reg _axmir_reg _axmir_new_insn _axmir_link \
         _axmir_func_addr _axmir_dump _MIR_new_module _MIR_finish_module \
         _MIR_new_func_arr _MIR_new_proto_arr _MIR_new_import _MIR_new_export \
         _MIR_new_forward _MIR_new_label _MIR_append_insn _MIR_finish_func \
         _MIR_load_module _MIR_load_external; do
  if nm -gU "$OUT" | grep -q " $s\$"; then echo "  $s ok"; else echo "  $s MISSING"; fi
done
