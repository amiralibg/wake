#!/bin/bash
# Packages a release build of the host as a .deb and an .rpm with nfpm:
#   Wake-<version>-linux-<arch>.deb   (Debian, Ubuntu, Mint, Pop!_OS…)
#   Wake-<version>-linux-<arch>.rpm   (Fedora, openSUSE, RHEL…)
#
#   cargo build --release --manifest-path desktop/host/Cargo.toml
#   desktop/packaging/linux/build-packages.sh [output folder]
#
# They depend on the distribution's WebKitGTK 4.1 (2.40 or later), so build on
# the oldest distribution you support: the binary needs its glibc or newer.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${1:-$ROOT/desktop/dist}
TOOLS=${TOOLS:-$ROOT/desktop/packaging/.tools}
NFPM_VERSION=2.47.0
ARCH=$(uname -m)
VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/desktop/host/Cargo.toml" | head -1)
BIN=${WAKE_BIN:-$ROOT/desktop/host/target/release/wake}
[ -x "$BIN" ] || { echo "No release build at $BIN" >&2; exit 1; }

case "$ARCH" in
  x86_64) NFPM_ARCH=amd64; TOOL_ARCH=x86_64 ;;
  aarch64 | arm64) ARCH=aarch64; NFPM_ARCH=arm64; TOOL_ARCH=arm64 ;;
  *) echo "Unsupported architecture $ARCH" >&2; exit 1 ;;
esac

if [ ! -x "$TOOLS/nfpm" ]; then
  mkdir -p "$TOOLS"
  curl -fsSL "https://github.com/goreleaser/nfpm/releases/download/v$NFPM_VERSION/nfpm_${NFPM_VERSION}_Linux_$TOOL_ARCH.tar.gz" | tar -xz -C "$TOOLS" nfpm
fi

mkdir -p "$OUT"
cd "$ROOT"
# nfpm expands variables in fields like the version, but not in file paths.
CONFIG=$(mktemp)
trap 'rm -f "$CONFIG"' EXIT
sed "s|\${WAKE_BIN}|$BIN|" desktop/packaging/linux/nfpm.yaml > "$CONFIG"
export NFPM_ARCH WAKE_VERSION="$VERSION"
for packager in deb rpm; do
  "$TOOLS/nfpm" package --config "$CONFIG" --packager "$packager" \
    --target "$OUT/Wake-$VERSION-linux-$ARCH.$packager"
done
