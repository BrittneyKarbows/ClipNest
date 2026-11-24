#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/../ClipNest.app}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DEST="${2:-$ROOT/../ClipNest-$VERSION-arm64.dmg}"
BUILD="${CLIPNEST_BUILD_DIR:-$ROOT/.build}"
PYTHON="${CLIPNEST_DMG_PYTHON:-python3}"
mkdir -p "$BUILD/cache" "$BUILD/dmg-background" "$(dirname "$DEST")"
if ! "$PYTHON" -c 'import dmgbuild' >/dev/null 2>&1; then
    echo "DMG build tools are missing. Install Scripts/requirements-dmg.txt in a Python virtual environment and set CLIPNEST_DMG_PYTHON to its Python executable." >&2
    exit 1
fi
codesign --verify --deep --strict "$APP"
xcrun swift -module-cache-path "$BUILD/cache" "$ROOT/Resources/GenerateDMGBackground.swift" "$BUILD/dmg-background" "$VERSION"
xcrun swiftc -module-cache-path "$BUILD/cache" "$ROOT/Scripts/DMGBookmark.swift" -o "$BUILD/dmg-bookmark"
"$PYTHON" "$ROOT/Scripts/build-dmg.py" \
    --app "$APP" --background "$BUILD/dmg-background/installer.png" \
    --icon "$ROOT/Resources/AppIcon-BlackWhite.icns" --license "$ROOT/LICENSE" \
    --bookmark-helper "$BUILD/dmg-bookmark" --output "$DEST"
hdiutil verify "$DEST"
echo "Built: $DEST"
