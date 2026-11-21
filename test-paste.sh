#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${CLIPNEST_BUILD_DIR:-$ROOT/.build}"
mkdir -p "$BUILD/cache"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD/cache" \
    "$ROOT/Sources/PasteService.swift" "$ROOT/Tests/PasteChecks.swift" \
    -o "$BUILD/PasteChecks" -framework Cocoa -framework ApplicationServices
"$BUILD/PasteChecks"
