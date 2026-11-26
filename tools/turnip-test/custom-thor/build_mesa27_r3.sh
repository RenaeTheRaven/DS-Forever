#!/bin/bash
# custom-thor: StevenMXZ's "Turnip v27.0.0-R3" (github.com/StevenMXZ/Adreno-Tools-Drivers, release v40, repo commit 4b796491,
# Mesa main c5ef4bdfabf2e1a76d5e41ab8e5d75ddbc121275) rebuilt so DS Forever's Vulkan wrapper can load it:
#   - their release exports only HMI; the wrapper loads drivers through the three vk_icd* entry points, so this adds upstream DS
#     Forever's export patch (../0001-android-export-vk_icd-entrypoints.diff, applied with ../mkpatch.py);
#   - -Dandroid-strict=false (same reason as our 26.3.1 build: no Android allowlist hiding KHR extensions DXVK 3 needs).
# Everything else is their build_turnip.sh: the same patches in the same order, the same NDK fixes, platform-sdk-version 36, but NDK
# r27c (theirs is r29) and --wrap-mode=nofallback (no downloads during configure).
#
#   PATH=~/dev/turnip-build/venv/bin:$PATH NDK=~/Android/Sdk/ndk/27.2.12479018 PATCHES=<their repo at 4b796491> W=<workdir> \
#     bash build_mesa27_r3.sh
# then: python3 -I pack_mesa27_r3.py "$W/pack-input" <out dir>
set -eo pipefail
: "${NDK:?}" "${PATCHES:?}" "${W:?}"
MESA_COMMIT=c5ef4bdfabf2e1a76d5e41ab8e5d75ddbc121275
HERE=$(cd "$(dirname "$0")" && pwd); S=$(cd "$HERE/.." && pwd)
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
SRC=$W/mesa; BUILD=$W/build; PREFIX=$W/install
[ "$(git -C "$PATCHES" rev-parse HEAD)" = 4b796491db77b896852354e5484a0ac839e63adc ] || { echo "PATCHES must be their repo at 4b796491"; exit 1; }
mkdir -p "$W"

if [ ! -f "$W/patched.stamp" ]; then
  rm -rf "$SRC"; mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" fetch -q --depth=1 https://gitlab.freedesktop.org/mesa/mesa.git "$MESA_COMMIT"
  git -C "$SRC" checkout -q --detach FETCH_HEAD
  cd "$SRC"
  ap() { git apply --check "$PATCHES/patches/$1"; git apply "$PATCHES/patches/$1"; echo "applied $1"; }
  # --- their apply_unified_patches, unchanged order ---
  ap a8xx/0001-device-compatibility.patch
  for s in a8xx/apply_a8xx_gpus.py a8xx/a8xx_gpu_ids.py a7xx/apply_a7xx_gen1_quirks.py \
           android/fix_gralloc_flushall.py android/add_aimapper_gralloc.py android/add_ubwc_swapchain_usage.py; do
    python3 -B "$PATCHES/patches/$s"; echo "ran $s"; done
  for p in "$PATCHES"/patches/a8xx/mesh-and-compute/*.patch; do ap "a8xx/mesh-and-compute/$(basename "$p")"; done
  ap a8xx/0002-scope-pipeline-and-mesh-to-a8xx.patch
  ap a7xx/0001-oneui-ubwc-hint.patch
  ap a6xx/0001-revert-d32s8-late-z-workaround.patch
  ap a6xx/0002-kgsl-context-recovery.patch
  ap common/tu-vauzi-mutable-ubwc.patch
  for s in a8xx/apply_a8xx_cat4_rpt.py a8xx/a8xx_resolve_cr_cntl.py a8xx/a8xx_lrz_color_mask.py a8xx/process_heap_usage.py; do
    python3 -B "$PATCHES/patches/$s"; echo "ran $s"; done
  grep -Fq 'U_GRALLOC_TYPE_AIMAPPER' src/util/u_gralloc/u_gralloc.h
  grep -Fq 'tu_process_heap_used' src/freedreno/vulkan/tu_device.cc
  # --- their apply_android_ndk_fixes ---
  sed -i 's/typedef const native_handle_t\* buffer_handle_t;/typedef void* buffer_handle_t;/g' include/android_stub/cutils/native_handle.h || true
  sed -i 's/, hnd->handle/, (void *)hnd->handle/g' src/util/u_gralloc/u_gralloc_fallback.c || true
  sed -i -E 's/([a-z_]+)->handle->/((const native_handle_t *)\1->handle)->/g' src/vulkan/runtime/vk_android.c || true
  sed -i 's/anb->handle->/((const native_handle_t *)anb->handle)->/g' src/vulkan/runtime/vk_android.c || true
  sed -i "/-Werror=gnu-empty-initializer/d" meson.build || true
  # --- DS Forever's vk_icd export patch (the only functional addition) ---
  python3 -I "$S/mkpatch.py" "$SRC"
  grep -q vk_icdGetInstanceProcAddr src/vulkan/vulkan-android.sym
  git -C "$SRC" diff > "$W/mesa27-r3-dsf.diff"
  touch "$W/patched.stamp"
fi

API=36
cat > "$W/android-aarch64.ini" <<EOF
[binaries]
ar = '$TC/llvm-ar'
c = ['$TC/aarch64-linux-android35-clang']
cpp = ['$TC/aarch64-linux-android35-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$TC/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$W/nopc', '/usr/bin/pkg-config']

[built-in options]
c_args = ['-D__ANDROID__', '-Wno-error', '-Wno-gnu-empty-initializer', '-Wno-deprecated-declarations', '-Wno-incompatible-pointer-types-discards-qualifiers', '-Wno-incompatible-pointer-types']
cpp_args = ['-D__ANDROID__', '-Wno-error', '-Wno-gnu-empty-initializer', '-Wno-deprecated-declarations', '-Wno-incompatible-pointer-types-discards-qualifiers', '-Wno-incompatible-pointer-types']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF
mkdir -p "$W/nopc"
rm -rf "$BUILD" "$PREFIX"
cd "$SRC"
meson setup "$BUILD" --wrap-mode=nofallback --cross-file "$W/android-aarch64.ini" --prefix "$PREFIX" --libdir lib \
  -Dbuildtype=release -Dstrip=true -Dplatforms=android -Dvideo-codecs= -Dplatform-sdk-version=$API -Dandroid-stub=true \
  -Dandroid-strict=false -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dvulkan-beta=true -Dfreedreno-kmds=kgsl \
  -Degl=disabled -Dandroid-libbacktrace=disabled -Dzstd=disabled -Dxmlconfig=disabled -Dllvm=disabled -Dvalgrind=disabled \
  -Dlibunwind=disabled -Dbuild-tests=false -Dwerror=false > "$W/setup.log" 2>&1 || { tail -40 "$W/setup.log"; exit 1; }
ninja -C "$BUILD" -j"$(nproc)" install > "$W/build.log" 2>&1 || { grep -nE "error:|FAILED" "$W/build.log" | head -30; exit 1; }

OUT=$W/pack-input; rm -rf "$OUT"; mkdir -p "$OUT/licenses"
cp "$PREFIX/lib/libvulkan_freedreno.so" "$W/mesa27-r3-dsf.diff" "$OUT/"
for f in "$SRC"/licenses/*; do [ -f "$f" ] && cp "$f" "$OUT/licenses/LICENSE-$(basename "$f")"; done
cp "$SRC/docs/license.rst" "$OUT/licenses/mesa-docs-license.rst"
cp "$PATCHES/LICENSE" "$OUT/licenses/StevenMXZ-Adreno-Tools-Drivers-LICENSE.txt"
cp "$PATCHES/CREDITS.md" "$OUT/licenses/StevenMXZ-Adreno-Tools-Drivers-CREDITS.md"
sha256sum "$OUT/libvulkan_freedreno.so"
echo "pack input: $OUT"
