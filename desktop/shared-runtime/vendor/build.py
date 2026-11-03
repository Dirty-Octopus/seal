#!/usr/bin/env python3
"""Build a thin app package and immutable, reusable Electron runtime archive.
Build-time Python only; target Macs use a compiled Swift installer helper.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
MACHO = {bytes.fromhex(x) for x in ('cffaedfe', 'cefaedfe', 'feedfacf', 'feedface', 'cafebabe', 'bebafeca')}

def run(*args):
    return subprocess.check_output([str(x) for x in args], stderr=subprocess.STDOUT).decode().strip()

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()

def inventory(root):
    result = []
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink(): result.append({'path': relative, 'target': os.readlink(path)})
            elif path.is_file(): result.append({'path': relative, 'sha256': digest(path)})
    return sorted(result, key=lambda x: x['path'])

def sign_tree(root, identity):
    # Explicit inside-out signing. Never sign a runtime after creating projections.
    paths = [p for p in root.rglob('*') if not p.is_symlink()]
    flags = ['--force', '--sign', identity]
    if identity != '-': flags += ['--options', 'runtime', '--timestamp']
    for p in paths:
        if p.is_file():
            with p.open('rb') as f: magic = f.read(4)
            if magic in MACHO: run('codesign', *flags, p)
    bundles = [p for p in paths if p.is_dir() and p.suffix in ('.app', '.framework', '.xpc')]
    if root.suffix in ('.app', '.framework', '.xpc'): bundles.append(root)
    for p in sorted(bundles, key=lambda x: len(x.parts), reverse=True):
        extra = ['--entitlements', HERE / 'entitlements.plist'] if p.suffix == '.app' else []
        run('codesign', *flags, *extra, p)

def notarize(artifact, profile):
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(artifact), '--keychain-profile', profile,
                             '--wait', '--output-format', 'json'], capture_output=True, text=True, check=True)
    submission = json.loads(result.stdout)
    if submission.get('status') != 'Accepted':
        raise ValueError(f'Notarization rejected: {submission}')

def project(source, target):
    shutil.copytree(source, target, symlinks=True, copy_function=os.link)

def build(source, output, identity='-', installer_identity=None, runtime_from=None, url_base=None, notary_profile=None):
    if identity != "-" and (not installer_identity or not notary_profile):
        raise ValueError("Distribution builds require --installer-identity and --notary-profile")
    source = source.resolve(); output = output.resolve()
    if output.exists(): raise ValueError(f'Refusing to overwrite output: {output}')
    output.mkdir(parents=True)
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    frameworks = source / 'Contents/Frameworks'
    names = sorted(p.name for p in frameworks.glob('*.framework'))
    if 'Electron Framework.framework' not in names: raise ValueError('Source is not a bundled Electron app')
    electron_info = plistlib.loads((frameworks / 'Electron Framework.framework/Resources/Info.plist').read_bytes())
    version = electron_info['CFBundleVersion']
    archs = run('lipo', '-archs', source / 'Contents/MacOS' / info['CFBundleExecutable'])
    if archs not in ('arm64', 'x86_64'): raise ValueError('Build one architecture at a time')
    arch = 'arm64' if archs == 'arm64' else 'x64'
    source_files = [e for e in inventory(frameworks) if e['path'].split('/')[0] in names]
    notices = ['LICENSE.electron.txt', 'LICENSES.chromium.html']
    source_files += [{'path': 'Notices/' + name, 'sha256': digest(source / 'Contents/Resources' / name)} for name in notices]
    fingerprint = hashlib.sha256(json.dumps(source_files, sort_keys=True).encode()).hexdigest()
    if runtime_from:
        runtime_from = runtime_from.resolve()
        runtime = runtime_from / 'runtime'
        meta = json.loads((runtime_from / 'runtime.json').read_text())
        if meta['sourceFingerprint'] != fingerprint or meta['signingIdentity'] != identity:
            raise ValueError('Runtime source/fuses/signing identity differ; do not mix these applications')
        if inventory(runtime) != meta['files']: raise ValueError('Runtime build directory has changed')
    else:
        runtime = output / 'runtime'; runtime.mkdir()
        for name in names: shutil.copytree(frameworks / name, runtime / name, symlinks=True)
        (runtime / 'Notices').mkdir()
        for name in notices: shutil.copy2(source / 'Contents/Resources' / name, runtime / 'Notices' / name)
        sign_tree(runtime, identity)
        # Runtime content is immutable. Updates get a new content-addressed directory.
        for p in runtime.rglob('*'):
            if p.is_file() and not p.is_symlink(): p.chmod(0o555 if p.stat().st_mode & 0o111 else 0o444)
        files = inventory(runtime)
        content_hash = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
        runtime_id = f'electron-{version}-{arch}-{content_hash[:16]}'
        archive = output / f'{runtime_id}.zip'
        run('ditto', '-c', '-k', '--norsrc', '--noextattr', runtime, archive)
        base = url_base or f'https://github.com/Dirty-Octopus/AYMDevKitUI/releases/download/runtime-{version}-{arch}-preview'
        meta = dict(schema=1, runtimeID=runtime_id, architecture=arch, electronVersion=version,
                    archiveURL=base.rstrip('/') + '/' + archive.name, archiveSHA256=digest(archive),
                    frameworks=names, files=files, sourceFingerprint=fingerprint, signingIdentity=identity)
        (output / 'runtime.json').write_text(json.dumps(meta, indent=2) + '\n')
    payload = output / 'payload'; payload.mkdir()
    thin = payload / source.name
    # Copy helpers and business assets; shared framework files are never in the pkg payload.
    shutil.copytree(source, thin, symlinks=True,
        ignore=lambda path, children: names if Path(path) == frameworks else [])
    # Sign this app's own helpers first, before projecting the already-signed runtime.
    sign_tree(thin, identity)
    for name in names: project(runtime / name, thin / 'Contents/Frameworks' / name)
    flags = ['--force', '--sign', identity, '--entitlements', str(HERE / 'entitlements.plist')]
    if identity != '-': flags += ['--options', 'runtime', '--timestamp']
    run('codesign', *flags, thin)
    run('codesign', '--verify', '--deep', '--strict', thin)
    if identity != '-':
        complete_zip = output / 'notarization-application.zip'
        run('ditto', '-c', '-k', '--keepParent', thin, complete_zip)
        notarize(complete_zip, notary_profile)
        run('xcrun', 'stapler', 'staple', thin)
        run('spctl', '--assess', '--type', 'execute', thin)
    for name in names: shutil.rmtree(thin / 'Contents/Frameworks' / name)
    app_zip = output / 'thin-application.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', thin, app_zip)
    app_sha = digest(app_zip)
    app_archive = output / f'{info["CFBundleIdentifier"]}-{info.get("CFBundleShortVersionString", "1.0")}-{arch}-{app_sha[:16]}.zip'
    app_zip.rename(app_archive)
    app_url = (url_base or meta['archiveURL'].rsplit('/', 1)[0]).rstrip('/') + '/' + app_archive.name
    manifest = {**meta, 'appBundle': source.name, 'bundleID': info['CFBundleIdentifier'],
                'appArchiveURL': app_url, 'appArchiveSHA256': app_sha, 'developmentPreview': identity == '-'}
    scripts = output / 'scripts'; scripts.mkdir()
    (scripts / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    helper = scripts / 'aym-runtime-installer'
    run('swiftc', '-O', '-target', f'{archs}-apple-macos13', HERE / 'RuntimeInstaller.swift',
        '-o', helper, '-framework', 'Foundation', '-framework', 'CryptoKit', '-framework', 'AppKit')
    run('codesign', *(['--force', '--sign', identity] + (['--options', 'runtime', '--timestamp'] if identity != '-' else [])), helper)
    for script, action in [('preinstall', 'prepare'), ('postinstall', 'install')]:
        path = scripts / script
        path.write_text('#!/bin/sh\nset -eu\nSCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\n'
                        f'exec "$SCRIPT_DIR/aym-runtime-installer" {action} "$SCRIPT_DIR/manifest.json" --volume "$3"\n')
        path.chmod(0o755)
    component = output / 'application.pkg'
    # The signed bootstrap contains no incomplete .app bundle. It downloads the
    # thin archive and reconstructs the original, fully signed/notarized app.
    run('pkgbuild', '--nopayload', '--identifier', info['CFBundleIdentifier'] + '.shared-runtime',
        '--version', info.get('CFBundleShortVersionString', '1.0'), '--scripts', scripts, component)
    product = output / f'{source.stem.replace(chr(32), chr(46))}-Shared-{arch}{"-Preview" if identity == "-" else ""}.pkg'
    requirements = output / 'requirements.plist'
    requirements.write_bytes(plistlib.dumps({'os': [info.get('LSMinimumSystemVersion', '13.0')], 'arch': [archs]}))
    sign = ['--sign', installer_identity] if installer_identity else []
    run('productbuild', '--package', component, '--product', requirements, *sign, product)
    if identity != '-':
        notarize(product, notary_profile)
        run('xcrun', 'stapler', 'staple', product)
        run('xcrun', 'stapler', 'validate', product)
    report = dict(application=str(thin), installer=str(product), manifest=str(scripts / 'manifest.json'),
                  runtimeDirectory=str(runtime), runtimeID=meta['runtimeID'], downloadURL=meta['archiveURL'],
                  signing='ad-hoc local testing only' if identity == '-' else identity,
                  notarized=identity != '-', applicationArchive=str(app_archive))
    (output / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app', type=Path, required=True)
    p.add_argument('--output', type=Path, default=HERE.parent / 'release' / ('shared-' + time.strftime('%Y%m%d-%H%M%S')))
    p.add_argument('--identity', default='-')
    p.add_argument('--installer-identity')
    p.add_argument('--notary-profile')
    p.add_argument('--runtime-from', type=Path)
    p.add_argument('--url-base')
    a = p.parse_args()
    print(json.dumps(build(a.app, a.output, a.identity, a.installer_identity, a.runtime_from, a.url_base, a.notary_profile), indent=2))
