#!/bin/sh
# Regenerates the README images in docs/ from the app's own drawing code.
set -e
cd "$(dirname "$0")/.."

mkdir -p build
# Everything except the app entry point (App.swift has its own @main).
swiftc -O -swift-version 5 -parse-as-library \
  $(ls Sources/*.swift | grep -v App.swift) \
  Tools/RenderAssets.swift \
  -o build/render-assets
build/render-assets docs
