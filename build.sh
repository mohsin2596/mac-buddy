#!/bin/sh
# Builds build/MacBuddy.app (universal: Apple silicon + Intel, macOS 14+)
# Usage: ./build.sh [version]
set -e
cd "$(dirname "$0")"

VERSION="${1:-}"
APP=build/MacBuddy.app
MIN_OS=14.0
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos$MIN_OS" \
    Sources/*.swift \
    -o "build/MacBuddy-$arch"
done
lipo -create build/MacBuddy-arm64 build/MacBuddy-x86_64 -output "$APP/Contents/MacOS/MacBuddy"
rm build/MacBuddy-arm64 build/MacBuddy-x86_64

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
