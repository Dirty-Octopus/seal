#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ ! -d desktop/node_modules ]; then npm ci --prefix desktop; fi
npm run desktop:build --prefix desktop
npm run runtime:build --prefix desktop -- --output "${SEAL_SHARED_OUTPUT:-$ROOT/dist/shared-arm64}" --replace
