#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash "$ROOT/scripts/build.sh"
SEAL_STANDALONE_ARCH=x64 bash "$ROOT/scripts/package_standalone.sh"
python3 - "$ROOT" "${SEAL_SHARED_OUTPUT:-$ROOT/dist/shared-arm64}" <<'PY'
from pathlib import Path
import hashlib,json,shutil,sys
root,shared=map(Path,sys.argv[1:])
version=json.loads((root/'desktop/package.json').read_text())['version']
arm=json.loads((shared/'build.json').read_text())
intel=json.loads((root/'dist/standalone-x64/build.json').read_text())
output=root/'dist/releases'/('v'+version);output.mkdir(parents=True,exist_ok=True)
assets=[Path(arm['installer']),Path(arm['applicationArchive']),Path(intel['dmg']),Path(intel['archive'])]
lines=[]
for source in assets:
    target=output/source.name;shutil.copy2(source,target)
    with target.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    lines.append(f'{digest}  {target.name}\n')
(output/'SHA256SUMS.txt').write_text(''.join(lines))
(output/'release.json').write_text(json.dumps(dict(version=version,assets=[file.name for file in assets]+['SHA256SUMS.txt'],sharedManifest=arm['manifest'],intelApplication=intel['application']),indent=2)+'\n')
print('Release artifacts:',output)
PY
