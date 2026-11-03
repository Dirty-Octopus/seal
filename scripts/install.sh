#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${1:-$ROOT/dist/shared-arm64/Seal-Shared-arm64-Preview.pkg}"
if [ ! -f "$PACKAGE" ]; then
    echo "Installer not found. Run bash scripts/build.sh first: $PACKAGE" >&2
    exit 1
fi
# The native package owns managed-folder installation and system authentication.
# Its pinned application ZIP must be available at the manifest's release URL.
/usr/bin/open "$PACKAGE"
