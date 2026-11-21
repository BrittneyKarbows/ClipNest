#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${CLIPNEST_BUILD_DIR:-$ROOT/.build}"
mkdir -p "$BUILD/cache"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD/cache" \
    "$ROOT/Sources/Models.swift" "$ROOT/Sources/HotKey.swift" "$ROOT/Sources/ClipStore.swift" "$ROOT/Sources/ClipboardService.swift" \
    "$ROOT/Tests/main.swift" -o "$BUILD/ClipNestTests" -framework Cocoa -framework Carbon -framework ServiceManagement -lsqlite3
"$BUILD/ClipNestTests"
