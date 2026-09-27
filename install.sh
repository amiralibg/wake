#!/bin/bash
# Installs the latest Wake, or updates an installed copy:
#
#   curl -fsSL https://raw.githubusercontent.com/amiralibg/wake/main/install.sh | bash
#
# Wake isn't signed with an Apple Developer ID yet, so macOS blocks a copy
# downloaded in a browser until you allow it. curl doesn't mark what it downloads
# as quarantined, so a copy installed this way opens straight away.
#
# Installs to /Applications, or ~/Applications if that isn't writable. Set
# WAKE_APP_DIR to choose another folder.
set -euo pipefail

FEED="https://github.com/amiralibg/wake/releases/latest/download/appcast.xml"
BUNDLE_ID="app.wake.Wake"

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "Wake is a macOS app."
MACOS=$(sw_vers -productVersion)
[ "${MACOS%%.*}" -ge 14 ] || fail "Wake needs macOS 14 or later; this Mac has $MACOS."

if [ -n "${WAKE_APP_DIR:-}" ]; then
  DIR=$WAKE_APP_DIR
elif [ -w /Applications ]; then
  DIR=/Applications
else
  DIR="$HOME/Applications"
fi
mkdir -p "$DIR"
APP="$DIR/Wake.app"

if [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2> /dev/null)" = true ]; then
  fail "Wake is running. Quit it (⌘Q), then run this again."
fi

# The appcast is what installed copies update from, so it always names the newest release.
APPCAST=$(curl -fsSL "$FEED") || fail "Couldn't reach GitHub."
URL=$(printf '%s' "$APPCAST" | sed -n 's/.*<enclosure url="\([^"]*\)".*/\1/p' | head -1)
VERSION=$(printf '%s' "$APPCAST" | sed -n 's/.*<sparkle:shortVersionString>\(.*\)<\/sparkle:shortVersionString>.*/\1/p' | head -1)
[ -n "$URL" ] || fail "Couldn't find the latest release in $FEED."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Wake $VERSION…"
curl -fL --progress-bar -o "$WORK/Wake.zip" "$URL" || fail "The download failed."
ditto -x -k "$WORK/Wake.zip" "$WORK" || fail "The download is damaged."
[ -d "$WORK/Wake.app" ] || fail "The download doesn't contain Wake.app."
[ "$(defaults read "$WORK/Wake.app/Contents/Info" CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "The download isn't Wake."
codesign --verify --deep --strict "$WORK/Wake.app" 2> /dev/null || fail "The download's code signature is broken."

# Swap it in whole, so a failure never leaves half an app behind.
xattr -dr com.apple.quarantine "$WORK/Wake.app" 2> /dev/null || true
rm -rf "$DIR/.Wake.app.new"
ditto "$WORK/Wake.app" "$DIR/.Wake.app.new"
rm -rf "$APP"
mv "$DIR/.Wake.app.new" "$APP"

echo "Installed Wake $VERSION in $DIR. It updates itself from now on."
if [ -z "${WAKE_NO_OPEN:-}" ]; then open "$APP"; fi
