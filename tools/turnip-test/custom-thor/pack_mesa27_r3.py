"""custom-thor: package build_mesa27_r3.sh's output (StevenMXZ Turnip v27.0.0-R3 + DS Forever's vk_icd export, android-strict off)
in DS Forever's driver-zip layout (flat entries, meta.json read by AdrenotoolsManager, licence texts, the source diff, SOURCE.txt).
Run: python3 -I pack_mesa27_r3.py <W/pack-input> <out dir>
Fixed entry times, so the same input gives the same zip (pinned in tools/components-test-drivers.sha256).
"""
import hashlib, json, os, sys, zipfile

B, OUT = sys.argv[1], sys.argv[2]
ZIP = os.path.join(OUT, "turnip-test-mesa-27.0-r3.zip")
DT = (2026, 11, 25, 0, 0, 0)
MESA = "c5ef4bdfabf2e1a76d5e41ab8e5d75ddbc121275"

meta = {
    "schemaVersion": 1,
    "name": "Turnip-Test-Mesa-27.0-R3-dsf",
    "description": f"OPT-IN TEST: StevenMXZ Turnip v27.0.0-R3 (Adreno-Tools-Drivers v40, Mesa main {MESA[:12]}) with its a6xx/a7xx/a8xx and "
                   "Android gralloc/UBWC patches; DS Forever rebuild adds the vk_icd* loader exports and -Dandroid-strict=false.",
    "author": "Mesa contributors; StevenMXZ (patches); DS Forever custom-thor rebuild",
    "packageVersion": "1",
    "vendor": "Mesa",
    "driverVersion": "27.0.0-devel-r3-dsf",
    "minApi": 29,
    "libraryName": "libvulkan_freedreno.so",
}

so = os.path.join(B, "libvulkan_freedreno.so")
diff = os.path.join(B, "mesa27-r3-dsf.diff")
so_sha = hashlib.sha256(open(so, "rb").read()).hexdigest()

source_txt = f"""Turnip-Test-Mesa-27.0-R3-dsf - source and build record (custom-thor)

Source: Mesa main at {MESA}
  https://gitlab.freedesktop.org/mesa/mesa/-/commit/{MESA}
Patches: StevenMXZ/Adreno-Tools-Drivers commit 4b796491db77b896852354e5484a0ac839e63adc
  (release v40, "Turnip v27.0.0-R3"), applied in the order of its build_turnip.sh,
  plus its Android NDK source fixes. Their licence (GPL-3.0) and CREDITS.md are in this zip.
DS Forever change: the vk_icd export patch (tools/turnip-test/mkpatch.py), so the
  Vulkan wrapper can load the library (their release exports only HMI).
The whole source difference from Mesa {MESA[:12]} is mesa27-r3-dsf.diff (in this zip).
Toolchain: Android NDK r27c (27.2.12479018), target aarch64-linux-android35,
  meson 1.12.1, ninja 1.13.2, CachyOS Linux.
Meson options: --wrap-mode=nofallback -Dbuildtype=release -Dstrip=true
  -Dplatforms=android -Dvideo-codecs= -Dplatform-sdk-version=36 -Dandroid-stub=true
  -Dandroid-strict=false -Dgallium-drivers= -Dvulkan-drivers=freedreno
  -Dvulkan-beta=true -Dfreedreno-kmds=kgsl -Degl=disabled
  -Dandroid-libbacktrace=disabled -Dzstd=disabled -Dxmlconfig=disabled
  -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dbuild-tests=false
  -Dwerror=false
libvulkan_freedreno.so sha256 {so_sha}
Licences: Mesa is mostly MIT; individual files carry their own SPDX terms
  (texts included). See mesa-docs-license.rst.
"""

os.makedirs(OUT, exist_ok=True)
if os.path.exists(ZIP):
    os.remove(ZIP)

def add(z, name, data):
    zi = zipfile.ZipInfo(name, DT)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.external_attr = 0o644 << 16
    z.writestr(zi, data, compresslevel=9)

with zipfile.ZipFile(ZIP, "w") as z:
    add(z, "libvulkan_freedreno.so", open(so, "rb").read())
    add(z, "meta.json", json.dumps(meta, indent=2) + "\n")
    lic = os.path.join(B, "licenses")
    for f in sorted(os.listdir(lic)):
        add(z, f, open(os.path.join(lic, f), "rb").read())
    add(z, "mesa27-r3-dsf.diff", open(diff, "rb").read())
    add(z, "SOURCE.txt", source_txt)

print(ZIP, os.path.getsize(ZIP), hashlib.sha256(open(ZIP, "rb").read()).hexdigest())
print("so", os.path.getsize(so), so_sha)
