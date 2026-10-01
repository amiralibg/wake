#!/bin/bash
# Packages a release build of the host as Wake-<version>-linux-<arch>.AppImage.
#
#   cargo build --release --manifest-path desktop/host/Cargo.toml
#   desktop/packaging/linux/build-appimage.sh [output folder]
#
# linuxdeploy (with its GTK plugin) bundles the libraries, and appimagetool packs
# the result; both are fetched into $TOOLS (default: desktop/packaging/.tools).
#
# WebKitGTK starts helper processes (WebKitWebProcess, WebKitNetworkProcess) from
# a path compiled into libwebkit2gtk. The bundled copy has that path rewritten
# from "/usr/lib/<triplet>/webkit2gtk-4.1" to "././/lib/<triplet>/webkit2gtk-4.1"
# ("/usr" to "././", the same length), and a start hook changes to $APPDIR/usr, so it finds the
# bundled helpers. This is the approach Tauri's AppImages use.
#
# Build on the oldest distribution you support: the AppImage uses its glibc.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${1:-$ROOT/desktop/dist}
TOOLS=${TOOLS:-$ROOT/desktop/packaging/.tools}
ARCH=$(uname -m)
VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/desktop/host/Cargo.toml" | head -1)
BIN=${WAKE_BIN:-$ROOT/desktop/host/target/release/wake}
# Not every CI machine (or container) has FUSE; the tools run unpacked instead.
export APPIMAGE_EXTRACT_AND_RUN=1

[ -x "$BIN" ] || { echo "No release build at $BIN" >&2; exit 1; }

fetch() { # url, file
  [ -x "$TOOLS/$2" ] && return
  mkdir -p "$TOOLS"
  curl -fsSL "$1" -o "$TOOLS/$2"
  chmod +x "$TOOLS/$2"
}
fetch "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage" linuxdeploy
fetch "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" linuxdeploy-plugin-gtk.sh
fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage" appimagetool
export PATH="$TOOLS:$PATH"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APPDIR=$WORK/Wake.AppDir
PACKAGING=$ROOT/desktop/packaging

install -Dm755 "$BIN" "$APPDIR/usr/bin/wake"
install -Dm644 "$PACKAGING/linux/wake.desktop" "$APPDIR/usr/share/applications/wake.desktop"
install -Dm644 "$PACKAGING/icons/wake-256.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/wake.png"
install -Dm644 "$PACKAGING/icons/wake-512.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/wake.png"

# WebKit's helper processes and injected bundle.
LIBDIR=$(pkg-config --variable=libdir webkit2gtk-4.1)
WEBKIT=$LIBDIR/webkit2gtk-4.1
[ -d "$WEBKIT" ] || { echo "WebKitGTK's helpers aren't at $WEBKIT" >&2; exit 1; }
BUNDLED_WEBKIT=$APPDIR/usr/lib/${LIBDIR#/usr/lib/}/webkit2gtk-4.1
mkdir -p "$(dirname "$BUNDLED_WEBKIT")"
cp -r "$WEBKIT" "$BUNDLED_WEBKIT"

mkdir -p "$APPDIR/apprun-hooks"
cat > "$APPDIR/apprun-hooks/wake-webkit.sh" <<'HOOK'
# libwebkit2gtk looks for its helpers relative to the working directory (see
# build-appimage.sh); Wake doesn't use the working directory otherwise.
cd "$APPDIR/usr"
HOOK

DEPLOY_GTK_VERSION=3 linuxdeploy \
  --appdir "$APPDIR" \
  --plugin gtk \
  --executable "$APPDIR/usr/bin/wake" \
  --desktop-file "$APPDIR/usr/share/applications/wake.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/256x256/apps/wake.png" \
  --deploy-deps-only "$BUNDLED_WEBKIT"

# Point the bundled libwebkit2gtk at the bundled helpers.
FROM="/usr/lib/${LIBDIR#/usr/lib/}/webkit2gtk-4.1"
TO="././/lib/${LIBDIR#/usr/lib/}/webkit2gtk-4.1"
PATCHED=0
for lib in "$APPDIR"/usr/lib/libwebkit2gtk-4.1.so*; do
  [ -f "$lib" ] && [ ! -L "$lib" ] || continue
  # Byte for byte (sed treats the library as text and mangles it).
  if python3 - "$lib" "$FROM" "$TO" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
assert len(old) == len(new)
data = open(path, 'rb').read()
if old not in data:
    sys.exit(1)
open(path, 'wb').write(data.replace(old, new))
PY
  then PATCHED=1; fi
done
[ "$PATCHED" = 1 ] || { echo "libwebkit2gtk wasn't bundled, or doesn't contain $FROM" >&2; exit 1; }

mkdir -p "$OUT"
NAME="Wake-$VERSION-linux-$ARCH.AppImage"
ARCH=$ARCH appimagetool --no-appstream "$APPDIR" "$OUT/$NAME"
echo "$OUT/$NAME"
