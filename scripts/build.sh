#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ ! -d desktop/node_modules ]; then npm ci --prefix desktop; fi
npm run desktop:build --prefix desktop
mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Seal.app"
/usr/bin/ditto "$ROOT/desktop/release/mac-arm64/Seal.app" "$ROOT/dist/Seal.app"
/usr/bin/xattr -cr "$ROOT/dist/Seal.app"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$ROOT/dist/Seal.app"
/usr/bin/codesign --verify --deep --strict "$ROOT/dist/Seal.app"
echo "Built for local testing: $ROOT/dist/Seal.app"
