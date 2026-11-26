# DS Forever — custom-thor fork

An unofficial fork of [Jreese702/DS-Forever](https://github.com/Jreese702/DS-Forever), tuned for the **AYN Thor with the
Snapdragon 8 Gen 2 (Adreno 740, 16 GB)**. It tracks every upstream release (branch `custom-thor-<version>`, currently
**1.0.41**); everything upstream does is unchanged except the points below. Not affiliated with or supported by upstream —
please don't report bugs from this build there.

It installs **beside** the official app (package `app.dsforever.custom`, name "DS Forever Custom", its own signing key, no
self-update) and shares the same `WoW Forever` game folder, so you can switch between the two.

## Results at a glance

All measured on one Thor, WoW Forever, 1280x720 render, frame generation x2 from a 30 fps base (60 Hz panel).
"GPU load" is clock-adjusted: busy % × current clock / 680 MHz max, so 100% = the GPU flat out.

| | Before | After |
|---|---|---|
| Displayed frame rate | ~40 fps, uneven (stock 1080p, no frame gen) | **59.6–59.7 fps**, 16.7 ms frames |
| Frame-gen frame limit | ignored: game ran uncapped at 33–40 fps, panel-bound | locked at **30.0** → 60 shown |
| Periodic freezes | 200–320 ms freeze **every 15 s** | **none** over 58 s |
| 33 ms hitches (per ~60 s) | 8 | 1 |
| GPU at the 30 → 60 target | 77% busy at 680 MHz, ~71 °C | 72–82% busy at **550–615 MHz**, **57–59 °C** |
| Graphics settings at a steady 60 | low textures, no shadows | **High textures, FXAA High, Fair shadows** |

The scenes for the GPU row were not identical (see the honest notes per change below), but every row was repeated in play.

## The changes, and why

### 1. Render at 1280x720 on the Adreno 740
Upstream renders the 740 at the panel's 1920x1080. Measured at a fixed spot with every limiter off, 1080p was **GPU-bound at
41–46 fps** (GPU 95–98% busy at its 680 MHz maximum). The Thor's 8 Elite profiles already render at 720p; this fork does the
same on the 740. A game-folder file `.ds-resolution` containing e.g. `1920x1080` overrides it.

### 2. A 30 fps limit option for frame generation
Upstream offers 40 / 60 / off. With Lossless Scaling frame generation x2, a **30 base gives an exact 60** on the 60 Hz panel:
first test 59.3 fps shown, every frame 16.7 ms, GPU 77% at 680 MHz. 40 x2 = 80 can't be shown on a 60 Hz panel.

### 3. The frame limit actually applies with frame generation on (bug fix, present upstream since 1.0.16)
With frame gen ≥ x2, `XServerScreen.applyFpsLimiterToEngines` switches off the renderer's and the Present extension's limiters
because "the lsfg-vk layer owns pacing", but DS Forever runs the **native** frame-gen backend, which got target 0. Result: the
limit you picked in Settings or the quick menu did nothing; the game ran uncapped at 33–40 fps and the panel couldn't keep up.
Fix: the Present extension keeps pacing the game unless the lsfg-vk *layer* backend is really active.
**Measured:** guest locked at 30.0, frame gen asks 60 Hz, "PANEL-BOUND" warnings gone.

### 4. X surface fixed at the game's resolution (`XServerView.fixSurfaceToScreen`)
Nothing sized the Android surface, so the X server's Vulkan renderer — compositing, **frame generation** and present — ran at
the full 1920x1080 even though the game draws 1280x720. Fixing the surface's buffers at the X screen's size lets the display
hardware do the upscale for free and gives LSFG **2.25× fewer pixels** (its flow pass drops to 640x360). Checked in
SurfaceFlinger: swapchain 1280x720, scaled by the display controller. A game-folder file `.ds-fullsurface` turns it off.

### 5. `ResampleQuality` no longer forced
DS Forever forced it to 0 on every start, which blocks WoW's own FSR 1.0 upscaler (`ResampleQuality 3`). Now it's yours to set.

### 6. DXVK 3.1.1 instead of 2.4.1
Stock [DXVK](https://github.com/doitsujin/dxvk) v3.1.1, built as plain Windows ARM64 DLLs (`tools/dxvk-custom/`). DXVK 2.6+
added a **tiler mode** for mobile GPUs (render-pass secondary command buffers, store-op discards, cached memory), auto-enabled on
Turnip — the log confirms `driverID 18, tiler mode on`. 3.x needs Vulkan 1.4, so the wrapper is asked for `vulkanVersion=1.4`.

Getting it to start needed one patch: DXVK creates a **mutable-format swapchain** (to draw sRGB views of the swap images), the
Winlator wrapper accepts the flag but its real images aren't mutable, and Turnip's debug driver aborts at `vk_image.c:569
"image_view->format == image->format"`. The patch skips the mutable swapchain (`tools/dxvk-custom/dxvk-3.1.1-custom-thor.patch`,
plus two log lines). First comparison, frame gen x2 and the limiter off: **guest 33–40 fps at GPU 88–91%** with 3.1.1 versus
**30–35 fps at 95–99%** with 2.4.1 earlier — different scenes, so treat it as indicative. A game-folder file `.ds-dxvk`
containing `2.4.1` goes back to the bundled 2.4.1 (read at every Play).

### 7. The 15-second freeze: WowCompanion's heartbeat spread over five frames
Measured with SurfaceFlinger frame timestamps: a **200–320 ms freeze exactly every 15 s**. That is the WowCompanion add-on's
heartbeat (`C_Timer.NewTicker(15, ...)`), which collected the action bars, equipment, player, map and bags, JSON-encoded ~53 KB
and flushed it, all inside one game frame. Timed in game: bar 20–24 ms, equipment 14–30, bags 17–18, encode 15–18, map 3, send
5–7 — **82–97 ms of Lua in a single frame**, which the frame generator turned into a visible stall.
`WC.heartbeatStaged()` does the identical work across five consecutive frames (`C_Timer.After(0)` chain; same message, same
dedup keys). Largest single stage now 31–33 ms.

| 58–60 s sample, limit 30, frame gen x2 | fps shown | freezes > 100 ms | 33 ms hitches |
|---|---|---|---|
| Before | 58.6 | 4 (every 15 s) | 8 |
| After | **59.7** | **0** | 1 |

The add-on manifest's md5 for `Core.lua` is updated to match; the manifest *set* number is upstream's, so upstream add-on updates
still install over it.

### 8. Spending the headroom on looks
With 3–7 in place the GPU had room left, so the in-game settings were raised one at a time and each step measured for 30 s
(Brackenwall Village at night, frame gen x2, limit 30). GPU load is clock-adjusted, average / peak:

| Setting | fps shown | GPU load | Kept |
|---|---|---|---|
| Starting point | 59.7 | 61% / 69% | |
| Textures High (`graphicsTextureResolution 2`) | 59.7 | 61% / 70% | ✅ |
| FXAA High (`ffxAntiAliasingMode 2`) | 59.7 | 63% / 71% | ✅ |
| Shadows Fair (`graphicsShadowQuality 1`) | 59.6 | 71% / 82% | ✅ |
| Fair shadows, 2 cascades instead of 3 | — | 71% / 81% (no saving) | ❌ |
| `shadowMode 1` | — | 70% / 78% (worse in daylight) | ❌ |
| View distance 2 | **58.8, 17 hitches** | 72% / 82% | ❌ |
| **Final mix** | **59.6** | **72% / 80%** | |

These are game settings, not code. Turn **off** DS Forever's Settings › Performance › *Low-memory graphics* on a 16 GB Thor, or it
puts textures back to low at every start.

### 9. Mesa 26.3.1 test driver that works with DXVK 3
Upstream 1.0.40 adds an opt-in "Test: Mesa 26.3.1" Turnip driver. With DXVK 3.1.1 it failed with **"Your 3D accelerator card is
not supported"**: DXVK found the GPU but skipped it — `Device does not support required feature 'khrLoadStoreOpNone'`.
Turnip always supports that extension, but upstream builds for Android API 29 with Mesa's `android-strict` option on, and Mesa's
Android allowlist only permits `VK_KHR_load_store_op_none` from API 35, so the driver hid it. This fork rebuilds the **same**
Mesa 26.3.1 tarball, patch and NDK r27c with `-Dandroid-strict=false` (`tools/turnip-test/custom-thor/`), shipped as
`turnip-test-mesa-26.3.1-nostrict.zip`. With it DXVK 3.1.1 starts, tiler mode on, guest 30.1–30.3 / 60 Hz, GPU 75–83% busy at
550–615 MHz. **Still experimental:** some UI elements (e.g. the personal resource bars) have been seen drawing as flat grey with
this driver; the default *Recommended* driver is unaffected.

### 10. Building on Linux, and DS Forever Desktop on Linux
Upstream builds on Windows. Small path fixes let the native helpers build with the Linux NDK, and `desktop/linux/` runs
DS Forever Desktop under Proton with a native Linux [Sunshine](https://github.com/LizardByte/Sunshine) (see its README).

## Building

Same as upstream (`./gradlew :app:assembleModernRelease`, JDK 17, Android SDK + NDK r27c), with your own keystore in
`WC_KEYSTORE` / `WC_KEYSTORE_PASS` / `WC_KEY_ALIAS` / `WC_KEY_PASS`. The git-ignored inputs:

- `app/src/main/assets/bundled_components/`: the four upstream components (`tools/fetch_components.sh`; the Proton wcp must be
  the trimmed one pinned in `tools/components-trimmed.sha256` — copying it out of the official APK is simplest), plus
  `dxvk-3.1.1-wow-aarch64-diag2.wcp` (`tools/dxvk-custom/build.sh`) and `turnip-test-mesa-26.3.1-nostrict.zip`
  (`tools/turnip-test/custom-thor/`).
- `app/src/main/assets/wow-session-bridge.exe` and the native libraries: as upstream documents.

## Licence

GPL-3.0, as upstream. DXVK is zlib; Mesa is mostly MIT (see the driver zip's licence files).
