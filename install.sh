#!/bin/sh
# Builds Mac Buddy from source, installs it to ~/Applications, connects it to Claude Code, and launches it.
# (Most people should download the DMG from GitHub Releases instead; see README.)
set -e
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift is required to build from source. Install the Xcode Command Line Tools:  xcode-select --install" >&2
  echo "Or skip building and download the app: https://github.com/mohsin2596/mac-buddy/releases/latest" >&2
  exit 1
fi

./build.sh

DEST="$HOME/Applications/MacBuddy.app"
mkdir -p "$HOME/Applications"
pkill -x MacBuddy 2>/dev/null || true
rm -rf "$DEST"
cp -R build/MacBuddy.app "$DEST"

"$DEST/Contents/MacOS/MacBuddy" --connect
open "$DEST"
echo "Mac Buddy is running. Right-click it for options, or open it again for Settings."
