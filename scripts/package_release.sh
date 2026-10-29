#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - scripts/Info.plist)"
APP="$ROOT/dist/Seal.app"
DMG="$ROOT/dist/Seal-${VERSION}-macos-universal.dmg"
ZIP="$ROOT/dist/Seal-${VERSION}-macos-universal.zip"
ARM_BUILD="$ROOT/.build-release-arm"
X86_BUILD="$ROOT/.build-release-x86"

echo "Building Seal $VERSION (arm64 + x86_64)…"
rm -rf "$ARM_BUILD" "$X86_BUILD" "$ROOT/dist/dmg-staging"
mkdir -p "$ROOT/dist"

swift build -c release --arch arm64 --scratch-path "$ARM_BUILD"
swift build -c release --arch x86_64 --scratch-path "$X86_BUILD"

ARM_BIN="$(swift build -c release --arch arm64 --scratch-path "$ARM_BUILD" --show-bin-path)/Seal"
X86_BIN="$(swift build -c release --arch x86_64 --scratch-path "$X86_BUILD" --show-bin-path)/Seal"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/usr/bin/lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/Seal"
chmod 755 "$APP/Contents/MacOS/Seal"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP"

echo "Architectures:"
/usr/bin/lipo -info "$APP/Contents/MacOS/Seal"

# DMG with an Applications shortcut.
mkdir -p "$ROOT/dist/dmg-staging"
/usr/bin/ditto "$APP" "$ROOT/dist/dmg-staging/Seal.app"
ln -s /Applications "$ROOT/dist/dmg-staging/Applications"
rm -f "$DMG"
/usr/bin/hdiutil create \
    -volname "Seal" \
    -srcfolder "$ROOT/dist/dmg-staging" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

# ZIP for users who prefer a plain app bundle.
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

(
    cd "$ROOT/dist"
    /usr/bin/shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt
)

rm -rf "$ARM_BUILD" "$X86_BUILD" "$ROOT/dist/dmg-staging"

echo
echo "Release artifacts:"
ls -lh "$DMG" "$ZIP" "$ROOT/dist/SHA256SUMS.txt"
echo
cat "$ROOT/dist/SHA256SUMS.txt"
