#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT/scripts/build.sh"
echo "Shared-runtime installer, thin application ZIP and checksums: ${SEAL_SHARED_OUTPUT:-$ROOT/dist/shared-arm64}"
