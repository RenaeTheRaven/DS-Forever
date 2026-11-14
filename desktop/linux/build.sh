#!/bin/bash
# custom-thor: builds DS Forever Desktop for a Linux PC and stages it (see README.md).
#
#   build.sh <version> <official DsForeverDesktop-<version>-win-x64.zip> <extracted Sunshine AppImage dir> <install dir>
#
# The official zip gives the add-ons (companion/) and licence files; the exe and DsfDesktop.Core.dll are built from this tree.
# Needs a .NET SDK (DOTNET, default ~/.dotnet/dotnet) and unzip.
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
VERSION=$1; ZIP=$2; SUNSHINE=$3; DEST=$4
HERE=$(dirname "$(readlink -f "$0")")
DOTNET=${DOTNET:-$HOME/.dotnet/dotnet}
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

"$DOTNET" build "$HERE/../src/DsfDesktop/DsfDesktop.csproj" -c Release -v q -p:Version="$VERSION"
"$DOTNET" build "$HERE/SunshineShim/SunshineShim.csproj" -c Release -v q -p:Version="$VERSION"

[ -x "$SUNSHINE/AppRun" ] || { echo "no AppRun in $SUNSHINE" >&2; exit 1; }
mkdir -p "$DEST"
rm -rf "$DEST/app.new"
mkdir "$DEST/app.new"
unzip -q "$ZIP" -d "$DEST/app.new"
# the Windows Sunshine can't capture under Wine: the stand-in takes its place (the Linux Sunshine is in $DEST/sunshine)
rm -rf "$DEST/app.new/sunshine"
mkdir "$DEST/app.new/sunshine-linux"
B="$HERE/../src/DsfDesktop/bin/Release"
cp "$B/DsForeverDesktop.exe" "$B/DsForeverDesktop.exe.config" "$B/DsfDesktop.Core.dll" "$DEST/app.new/"
cp "$HERE/SunshineShim/bin/Release/sunshine.exe" "$DEST/app.new/sunshine-linux/"
rm -rf "$DEST/app"
mv "$DEST/app.new" "$DEST/app"
if [ "$(readlink -f "$SUNSHINE")" != "$(readlink -f "$DEST/sunshine")" ]; then
    rm -rf "$DEST/sunshine"
    cp -a "$SUNSHINE" "$DEST/sunshine"
fi
install -m 755 "$HERE/ds-forever-desktop" "$HERE/dsf-sunshine-helper.py" "$DEST/"
echo "staged DS Forever Desktop $VERSION for Linux in $DEST"
