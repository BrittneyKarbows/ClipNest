#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$ROOT/../ClipNest.app}"
BUILD="${CLIPNEST_BUILD_DIR:-$ROOT/.build}"
mkdir -p "$BUILD/cache" "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
xcrun swiftc -swift-version 5 -O -module-cache-path "$BUILD/cache" -target arm64-apple-macosx13.0 \
    "$ROOT"/Sources/*.swift -o "$DEST/Contents/MacOS/ClipNest" \
    -framework Cocoa -framework SwiftUI -framework Carbon -framework ApplicationServices -framework ServiceManagement -lsqlite3
cp "$ROOT/Resources/Info.plist" "$DEST/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$DEST/Contents/Resources/AppIcon.icns"
codesign --force --sign "${CLIPNEST_SIGN_IDENTITY:--}" --identifier com.clipnest.mac "$DEST"
echo "Built: $DEST"
