#!/bin/sh
# Builds release artifacts in dist/:
#   MacBuddy.dmg  drag-to-Applications disk image
#   MacBuddy.zip  used by scripts/get.sh (the one-line installer)
# Usage: scripts/make-release.sh 1.1.0
set -e
cd "$(dirname "$0")/.."

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Usage: scripts/make-release.sh <version>   e.g. 1.1.0" >&2
  exit 1
fi

./build.sh "$VERSION"

rm -rf dist
mkdir -p dist
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Zip (ditto keeps the code signature and extended attributes intact).
ditto -c -k --keepParent build/MacBuddy.app dist/MacBuddy.zip

# DMG with an Applications shortcut to drag onto.
cp -R build/MacBuddy.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Mac Buddy" -srcfolder "$STAGE" -ov -format UDZO dist/MacBuddy.dmg

echo
ls -lh dist
echo
echo "Next: create a GitHub release tagged v$VERSION and upload both files from dist/ (keep the names"
echo "MacBuddy.dmg and MacBuddy.zip so the README's 'latest' download links keep working):"
echo "  https://github.com/mohsin2596/mac-buddy/releases/new?tag=v$VERSION"
