# DS Forever Desktop on a Linux PC (custom-thor)

Upstream ships Desktop for Windows only. This folder runs the same app on a Linux PC where WoW runs under Proton:

- **Desktop itself** (`DsForeverDesktop.exe`, built from this tree) runs under Proton **in the game's own prefix**, on the Mono
  that Proton bundles. WoW and Battle.net are then ordinary windows to it, and the game folder, registry and add-on install work
  unchanged.
- **Sunshine** is the native Linux build (the extracted AppImage). The Windows one can't capture a screen under Wine. Desktop
  starts `sunshine-linux/sunshine.exe` instead, a stand-in (`SunshineShim/`) that rewrites Desktop's config for Linux
  (`sunshine.linux.conf`) and asks `dsf-sunshine-helper.py`, which the launcher runs outside Proton's container, to run the real
  one. The helper ends Sunshine when the stand-in goes, so Desktop's start, stop and restart work as on Windows.
- `ds-forever-desktop` is the launcher: it makes the bridge's TLS certificate once (openssl), starts the helper and then Desktop.

What the core needed (`Host.Wine`, all marked `custom-thor`): the bridge certificate is taken from the launcher instead of made
with `CertificateRequest` (Mono has none); Sunshine's API certificate is checked through the process-wide callback (Mono ignores
the handler's); the port check tries the ports (Wine's listener table has no Linux programs); no ViGEmBus check (Linux Sunshine
uses uinput); no self-update (the official zip is the Windows build).

## Build and install

    desktop/linux/build.sh 0.2.27 DsForeverDesktop-0.2.27-win-x64.zip <extracted Sunshine AppImage> ~/Applications/DSForeverDesktop-linux
    ~/Applications/DSForeverDesktop-linux/ds-forever-desktop

Needs a .NET SDK (`~/.dotnet/dotnet`, or `DOTNET=`), `umu-run`, `python3`, `openssl`, and read/write access to `/dev/uinput`.
The official zip supplies the add-ons (`companion/`); the Sunshine AppImage is extracted with `--appimage-extract`.

## Settings

- `~/.config/dsforever-desktop/env`: the Proton prefix, runner and game id WoW is started with (Faugus Launcher's by default).
- `~/.config/dsforever-desktop/sunshine-extra.conf`: extra Sunshine settings, for example `output_name = DP-3` for the monitor.
- Logs: `~/.local/share/dsforever-desktop/` (helper, Sunshine console, Desktop console); Desktop's own log and data are in the
  prefix, `drive_c/users/steamuser/AppData/Local/DSForeverDesktop`.

## Things to know

- Capture is the XDG portal (PipeWire): the first start asks once, on the PC's screen, which screen to share.
- The firewall must let the Thor in: TCP 48210 (bridge), Sunshine's TCP 47984, 47989, 48010 and UDP 47998-48000, and UDP 5353
  (mDNS).
- Sunshine streams the monitor as it is; "match the stream's resolution" is a Windows-only Sunshine feature and is dropped.
- Tests under Proton: build `tests/DsfDesktop.Tests` and run `DsfDesktop.Tests.exe` with `DSF_BRIDGE_SEED` set to a PFX made as
  the launcher does; `--sunshine <dir of the stand-in>` with the helper running does the live PIN pairing.
