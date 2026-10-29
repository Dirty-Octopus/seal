#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
cd "$ROOT"

# Xcode's toolchain ships the SwiftUI macro plugin; Command Line Tools alone does not.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [ ! -f Resources/AppIcon.icns ] || [ "${SEAL_REGEN_ICON:-0}" = "1" ]; then
    if python3 -c "import PIL" >/dev/null 2>&1; then
        python3 scripts/make_icon.py >/dev/null
    else
        echo "warning: Pillow not found; keeping existing Resources/AppIcon.icns" >&2
    fi
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Seal"

APP="$ROOT/dist/Seal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Seal"
chmod 755 "$APP/Contents/MacOS/Seal"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj "$APP/Contents/Resources/"
cp -R Resources/zh-Hans.lproj "$APP/Contents/Resources/"

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null

echo "Built: $APP"
/usr/bin/codesign -dvv "$APP" 2>&1 | sed -n '1,12p'
