#!/bin/bash
# custom-thor: DXVK 3.1.1 for DS Forever on the AYN Thor, built as plain Windows ARM64 PE DLLs (dxgi.dll, d3d11.dll) and packed as
# bundled_components/dxvk-3.1.1-wow-aarch64-diag2.wcp (git-ignored like the other bundled components).
#
#   tools/dxvk-custom/build.sh <llvm-mingw dir> <work dir>
#
# Needs: git, meson + ninja, glslangValidator, zstd, and llvm-mingw 20261104 (ucrt, x86_64 Linux host) from
# https://github.com/mstorsjo/llvm-mingw/releases (DXVK 2.7.x needs the older 20250826 instead; 3.1.1 builds with either).
# Source: https://github.com/doitsujin/dxvk tag v3.1.1 (b1a1c99) + dxvk-3.1.1-custom-thor.patch. DXVK is zlib-licensed.
set -euo pipefail
MINGW=$(readlink -f "$1"); W=$(readlink -f "$2"); HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/../../app/src/main/assets/bundled_components/dxvk-3.1.1-wow-aarch64-diag2.wcp
mkdir -p "$W"; cd "$W"
[ -d dxvk-3.1.1 ] || git clone --branch v3.1.1 --depth 1 --recurse-submodules --shallow-submodules https://github.com/doitsujin/dxvk dxvk-3.1.1
git -C dxvk-3.1.1 apply --check "$HERE/dxvk-3.1.1-custom-thor.patch" 2>/dev/null && git -C dxvk-3.1.1 apply "$HERE/dxvk-3.1.1-custom-thor.patch"
sed "s|@LLVM_MINGW@|$MINGW|" "$HERE/aarch64-windows.ini.in" > aarch64-windows.ini
(cd dxvk-3.1.1 && meson setup --cross-file ../aarch64-windows.ini --buildtype release -Db_ndebug=if-release --strip ../build-3.1.1)
ninja -C build-3.1.1
rm -rf pkg; mkdir -p pkg/system32 pkg/licenses
cp build-3.1.1/src/dxgi/dxgi.dll build-3.1.1/src/d3d11/d3d11.dll pkg/system32/
cp dxvk-3.1.1/LICENSE pkg/licenses/DXVK.txt
cp "$HERE/profile.json" pkg/
tar --owner=0 --group=0 --numeric-owner -C pkg -cf - . | zstd -19 -f -o "$OUT"
sha256sum "$OUT"
