#!/usr/bin/env python3
"""Build Seal's thin installer against the published, pinned AYM runtime."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
DESKTOP = HERE.parent
spec = importlib.util.spec_from_file_location('aym_builder', HERE / 'vendor/build.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
PIN = json.loads((HERE / 'runtime-arm64.json').read_text())
MARKER = 'seal-shared-runtime-v1'


def verify_runtime(runtime):
    if builder.inventory(runtime) != PIN['files']:
        raise ValueError('Shared runtime cache changed; refusing to reuse it')
    for name in PIN['frameworks']:
        builder.run('/usr/bin/codesign', '--verify', '--deep', '--strict', runtime / name)


def prepare_runtime(cache_root):
    """Fetch only when absent. This app never builds/publishes its own Electron archive."""
    cache_root.mkdir(parents=True, exist_ok=True)
    cache = cache_root / PIN['runtimeID']
    if cache.exists():
        if json.loads((cache / 'runtime.json').read_text()) != PIN:
            raise ValueError('Shared runtime cache metadata differs from the pinned release')
        verify_runtime(cache / 'runtime')
        return cache
    archive = cache_root / (PIN['runtimeID'] + '.zip')
    if not archive.exists():
        temporary = cache_root / ('.download-' + uuid.uuid4().hex)
        try:
            builder.run('/usr/bin/curl', '--fail', '--location', '--silent', '--show-error',
                        '--proto', '=https', '--proto-redir', '=https', '--retry', '2',
                        '--connect-timeout', '20', '--max-time', '600', '--output', temporary,
                        PIN['archiveURL'])
            if builder.digest(temporary) != PIN['archiveSHA256']:
                raise ValueError('Official runtime download SHA-256 mismatch')
            temporary.rename(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if builder.digest(archive) != PIN['archiveSHA256']:
        raise ValueError('Cached runtime ZIP SHA-256 mismatch')
    stage = Path(tempfile.mkdtemp(prefix='.seal-runtime-', dir=cache_root))
    try:
        builder.run('/usr/bin/ditto', '-x', '-k', archive, stage / 'runtime')
        verify_runtime(stage / 'runtime')
        (stage / 'runtime.json').write_text(json.dumps(PIN, indent=2) + '\n')
        try:
            stage.rename(cache)
        except OSError:
            if not cache.exists():
                raise
            if json.loads((cache / 'runtime.json').read_text()) != PIN:
                raise ValueError('Concurrent runtime preparation used different metadata')
            verify_runtime(cache / 'runtime')
        return cache
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def build(app, output, cache_root, url_base, replace=False):
    app, output = app.resolve(), output.resolve()
    if output.exists():
        receipt = output / 'build.json'
        if not replace or not receipt.is_file() or json.loads(receipt.read_text()).get('integration') != MARKER:
            raise ValueError('Output exists and is not a replaceable Seal shared-runtime build')
    package = json.loads((DESKTOP / 'package.json').read_text())
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.andyyu.seal' or info['CFBundleShortVersionString'] != package['version']:
        raise ValueError('Build the current Seal app before packaging it')
    if builder.run('/usr/bin/lipo', '-archs', app / 'Contents/MacOS/Seal') != 'arm64':
        raise ValueError('The pinned upstream shared-runtime preview supports arm64 only')
    if package['devDependencies']['electron'] != PIN['electronVersion']:
        raise ValueError('Electron dependency differs from the pinned shared runtime')
    # The custom Electron distribution used by the standalone builder stores its
    # notices outside Electron.app. Preserve them in both the app and runtime.
    resources = app / 'Contents/Resources'
    for source, name in [('LICENSE', 'LICENSE.electron.txt'), ('LICENSES.chromium.html', 'LICENSES.chromium.html')]:
        file = DESKTOP / 'node_modules/electron/dist' / source
        shutil.copy2(file, resources / name)
    cache = prepare_runtime(cache_root)
    output.parent.mkdir(parents=True, exist_ok=True)
    stage_parent = Path(tempfile.mkdtemp(prefix='.seal-shared-', dir=output.parent))
    stage = stage_parent / 'package'
    backup = output.with_name('.' + output.name + '-previous-' + uuid.uuid4().hex)
    try:
        report = builder.build(app, stage, runtime_from=cache, url_base=url_base)
        local_app = stage / 'local/Seal.app'
        local_app.parent.mkdir()
        shutil.copytree(stage / 'payload/Seal.app', local_app, symlinks=True)
        for name in PIN['frameworks']:
            builder.project(cache / 'runtime' / name, local_app / 'Contents/Frameworks' / name)
        builder.run('/usr/bin/codesign', '--verify', '--deep', '--strict', local_app)
        if any(stage.glob('electron-*.zip')):
            raise ValueError('Unexpected per-application runtime archive')
        # The application cache is a development artifact; production installation
        # uses the root-owned /Applications/Andy Yu/Runtime cache in the native helper.
        report.update(integration=MARKER, localApplication=str(local_app), version=package['version'],
                      sharedRuntimeReused=True, runtimeArchiveIncluded=False,
                      minimumSystemVersion=info.get('LSMinimumSystemVersion', '14.0'))
        report = {k: v.replace(str(stage), str(output), 1) if isinstance(v, str) and v.startswith(str(stage)) else v for k, v in report.items()}
        (stage / 'runtime-reference.json').write_text(json.dumps(PIN, indent=2) + '\n')
        (stage / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
        artifacts = [Path(report['installer']).name, Path(report['applicationArchive']).name]
        (stage / 'SHA256SUMS.txt').write_text(''.join(f'{builder.digest(stage / name)}  {name}\n' for name in artifacts))
        if output.exists():
            output.rename(backup)
        try:
            stage.rename(output)
        except OSError:
            if backup.exists():
                backup.rename(output)
            raise
        if backup.exists():
            shutil.rmtree(backup)
        return report
    finally:
        shutil.rmtree(stage_parent, ignore_errors=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=DESKTOP / 'release/mac-arm64/Seal.app')
    parser.add_argument('--output', type=Path, default=DESKTOP.parent / 'dist/shared-arm64')
    parser.add_argument('--cache', type=Path, default=Path(os.environ.get('SEAL_SHARED_CACHE', Path.home() / 'Library/Caches/Andy Yu/SharedElectron')))
    parser.add_argument('--url-base', help='Immutable HTTPS location for the Seal application ZIP, separate from the upstream runtime URL')
    parser.add_argument('--replace', action='store_true', help='Replace only a previous successful Seal shared-runtime build')
    args = parser.parse_args()
    version = json.loads((DESKTOP / 'package.json').read_text())['version']
    base = args.url_base or f'https://github.com/Dirty-Octopus/seal/releases/download/v{version}'
    if not base.startswith('https://'):
        raise ValueError('The production application archive URL must use HTTPS')
    print(json.dumps(build(args.app, args.output, args.cache, base, args.replace), indent=2))
