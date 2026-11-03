#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ ! -d desktop/node_modules ]; then npm ci --prefix desktop; fi
STANDALONE_ARCH="${SEAL_STANDALONE_ARCH:-x64}"
case "$STANDALONE_ARCH" in
    x64) BUILD_SCRIPT="desktop:intel"; BUILD_FOLDER="mac"; FILE_LABEL="intel" ;;
    universal) BUILD_SCRIPT="desktop:universal"; BUILD_FOLDER="mac-universal"; FILE_LABEL="universal" ;;
    *) echo "Unsupported standalone architecture: $STANDALONE_ARCH" >&2; exit 1 ;;
esac
if [ -n "${SEAL_ELECTRON_DIST:-}" ]; then
    npm run "$BUILD_SCRIPT" --prefix desktop -- --config.electronDist="$SEAL_ELECTRON_DIST"
else
    npm run "$BUILD_SCRIPT" --prefix desktop
fi
VERSION="$(node -p "require('./desktop/package.json').version")"
OUTPUT="$ROOT/dist/standalone-$STANDALONE_ARCH"
APP="$OUTPUT/Seal.app"
mkdir -p "$OUTPUT"
rm -rf "$APP" "$OUTPUT/dmg-staging"
/usr/bin/ditto "$ROOT/desktop/release/$BUILD_FOLDER/Seal.app" "$APP"
python3 - "$ROOT" "$APP" <<'PY'
from pathlib import Path
import shutil,sys
root,app=map(Path,sys.argv[1:])
for src,dst in [('LICENSE','LICENSE.electron.txt'),('LICENSES.chromium.html','LICENSES.chromium.html')]:
    shutil.copy2(root/'desktop/node_modules/electron/dist'/src,app/'Contents/Resources'/dst)
PY
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
mkdir -p "$OUTPUT/dmg-staging"
/usr/bin/ditto "$APP" "$OUTPUT/dmg-staging/Seal.app"
ln -s /Applications "$OUTPUT/dmg-staging/Applications"
DMG="$ROOT/dist/Seal-$VERSION-macos-$FILE_LABEL.dmg"
ZIP="$ROOT/dist/Seal-$VERSION-macos-$FILE_LABEL.zip"
/usr/bin/hdiutil create -volname Seal -srcfolder "$OUTPUT/dmg-staging" -ov -format UDZO "$DMG"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
python3 - "$APP" "$DMG" "$ZIP" "$STANDALONE_ARCH" "$OUTPUT" <<'PY'
import json,subprocess,sys
from pathlib import Path
app,dmg,archive,arch,output=sys.argv[1:]
actual=subprocess.check_output(['/usr/bin/lipo','-archs',app+'/Contents/MacOS/Seal'],text=True).split()
assert set(actual)==({'x86_64'} if arch=='x64' else {'arm64','x86_64'}),actual
Path(output,'build.json').write_text(json.dumps(dict(application=app,dmg=dmg,archive=archive,architecture=arch),indent=2)+'\n')
PY
rm -rf "$OUTPUT/dmg-staging"
echo "Standalone $STANDALONE_ARCH packages: $DMG and $ZIP"
