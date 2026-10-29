#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ ! -d desktop/node_modules ]; then npm ci --prefix desktop; fi
npm run desktop:universal --prefix desktop
VERSION="$(node -p "require('./desktop/package.json').version")"
mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Seal.app" "$ROOT/dist/dmg-staging"
/usr/bin/ditto "$ROOT/desktop/release/mac-universal/Seal.app" "$ROOT/dist/Seal.app"
/usr/bin/xattr -cr "$ROOT/dist/Seal.app"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$ROOT/dist/Seal.app"
/usr/bin/codesign --verify --deep --strict "$ROOT/dist/Seal.app"
mkdir -p "$ROOT/dist/dmg-staging"
/usr/bin/ditto "$ROOT/dist/Seal.app" "$ROOT/dist/dmg-staging/Seal.app"
ln -s /Applications "$ROOT/dist/dmg-staging/Applications"
/usr/bin/hdiutil create -volname Seal -srcfolder "$ROOT/dist/dmg-staging" -ov -format UDZO "$ROOT/dist/Seal-$VERSION-macos-universal.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/Seal.app" "$ROOT/dist/Seal-$VERSION-macos-universal.zip"
(cd "$ROOT/dist" && /usr/bin/shasum -a 256 "Seal-$VERSION-macos-universal.dmg" "Seal-$VERSION-macos-universal.zip" > SHA256SUMS.txt)
rm -rf "$ROOT/dist/dmg-staging"
echo "Local packages: $ROOT/dist"
