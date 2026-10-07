#!/bin/sh
# One-line installer for the latest Mac Buddy release:
#   curl -fsSL https://raw.githubusercontent.com/mohsin2596/mac-buddy/main/scripts/get.sh | sh
set -e

URL="https://github.com/mohsin2596/mac-buddy/releases/latest/download/MacBuddy.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Mac Buddy…"
curl -fL --progress-bar "$URL" -o "$TMP/MacBuddy.zip"
ditto -x -k "$TMP/MacBuddy.zip" "$TMP"

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

pkill -x MacBuddy 2>/dev/null || true
rm -rf "$DEST/MacBuddy.app"
ditto "$TMP/MacBuddy.app" "$DEST/MacBuddy.app"
xattr -dr com.apple.quarantine "$DEST/MacBuddy.app" 2>/dev/null || true

"$DEST/MacBuddy.app/Contents/MacOS/MacBuddy" --connect
open "$DEST/MacBuddy.app"
echo "Installed to $DEST/MacBuddy.app. Restart any open Claude Code sessions to see your buddy react."
