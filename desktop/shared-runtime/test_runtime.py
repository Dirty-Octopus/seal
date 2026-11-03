#!/usr/bin/env python3
"""Exercise the real Swift installer and two real Seal processes in a private root."""
import functools
import http.server
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('seal_build', HERE / 'build_seal.py')
integration = importlib.util.module_from_spec(spec); spec.loader.exec_module(integration)
builder = integration.builder
artifact = Path(sys.argv[1]).resolve()
base = json.loads((artifact / 'scripts/manifest.json').read_text())
helper = artifact / 'scripts/aym-runtime-installer'
receipt = json.loads((artifact / 'build.json').read_text())
runtime_source = Path(receipt['runtimeDirectory'])
archive_source = runtime_source.parent.parent / (base['runtimeID'] + '.zip')
root = Path(tempfile.mkdtemp(prefix='seal-shared-test-')).resolve()
(root / '.aym-runtime-test-root').touch()
web = root / 'web'; web.mkdir()
os.link(archive_source, web / archive_source.name)
requests = []
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path); super().do_GET()
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(web)))
threading.Thread(target=server.serve_forever, daemon=True).start()
address = f'http://127.0.0.1:{server.server_port}'
suite = root / 'Applications/Andy Yu'
evidence = artifact / 'test-evidence'; evidence.mkdir(exist_ok=True)

def invoke(action, manifest, test_root=root, success=True):
    result = subprocess.run([str(helper), action, str(manifest), '--test-root', str(test_root)], capture_output=True, text=True)
    if success and result.returncode: raise AssertionError(result.stderr)
    if not success and not result.returncode: raise AssertionError('Unsafe installation was unexpectedly accepted')
    return result.stdout + result.stderr

def fixture(label):
    bundle = f'Seal Runtime Test {label}.app'
    bundle_id = f'com.andyyu.seal.runtime-test.{label.lower()}'
    thin = root / 'fixtures' / bundle
    shutil.copytree(artifact / 'payload/Seal.app', thin, symlinks=True)
    info_path = thin / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes()); info['CFBundleIdentifier'] = bundle_id; info['CFBundleDisplayName'] = bundle[:-4]
    info_path.write_bytes(plistlib.dumps(info))
    for index, helper_info in enumerate(sorted((thin / 'Contents/Frameworks').glob('*.app/Contents/Info.plist'))):
        data = plistlib.loads(helper_info.read_bytes()); data['CFBundleIdentifier'] = bundle_id + f'.helper{index}'
        helper_info.write_bytes(plistlib.dumps(data))
    builder.sign_tree(thin, '-')
    for name in base['frameworks']: builder.project(runtime_source / name, thin / 'Contents/Frameworks' / name)
    builder.run('codesign', '--force', '--sign', '-', '--entitlements', HERE / 'vendor/entitlements.plist', thin)
    builder.run('codesign', '--verify', '--deep', '--strict', thin)
    for name in base['frameworks']: shutil.rmtree(thin / 'Contents/Frameworks' / name)
    archive = web / f'seal-test-{label}.zip'
    builder.run('ditto', '-c', '-k', '--keepParent', thin, archive)
    manifest = {**base, 'appBundle': bundle, 'bundleID': bundle_id, 'archiveURL': address + '/' + archive_source.name,
                'appArchiveURL': address + '/' + archive.name, 'appArchiveSHA256': builder.digest(archive)}
    manifest_path = root / f'manifest-{label}.json'; manifest_path.write_text(json.dumps(manifest))
    return suite / bundle, manifest_path

try:
    a, am = fixture('A'); b, bm = fixture('B')
    assert 'DOWNLOADED' in invoke('prepare', am)
    assert requests.count('/' + archive_source.name) == 1
    assert 'INSTALLED' in invoke('install', am)
    assert 'REUSED' in invoke('prepare', bm)
    assert 'INSTALLED' in invoke('install', bm)
    assert requests.count('/' + archive_source.name) == 1, 'Runtime downloaded again for the second app'
    shared = suite / 'Runtime' / base['runtimeID']
    shared_files = 0
    for entry in base['files']:
        if 'sha256' not in entry or entry['path'].split('/')[0] not in base['frameworks']: continue
        original = (shared / entry['path']).stat()
        for app in [a, b]:
            linked = (app / 'Contents/Frameworks' / entry['path']).stat()
            assert (original.st_dev, original.st_ino) == (linked.st_dev, linked.st_ino)
        shared_files += 1
    for app in [a, b]: builder.run('codesign', '--verify', '--deep', '--strict', app)
    badroot = root / 'bad-download'; badroot.mkdir(); (badroot / '.aym-runtime-test-root').touch()
    bad = root / 'bad-runtime.json'; bad.write_text(json.dumps({**json.loads(am.read_text()), 'archiveSHA256': '0' * 64}))
    assert 'checksum mismatch' in invoke('prepare', bad, badroot, success=False)
    assert not (badroot / 'Applications/Andy Yu/Runtime' / base['runtimeID']).exists()
    assert 'Test root marker missing' in invoke('prepare', am, root / 'unmarked', success=False)
    entry = next(item for item in base['files'] if 'sha256' in item and item['path'].endswith('Info.plist'))
    changed = shared / entry['path']; saved, mode = changed.read_bytes(), changed.stat().st_mode
    try:
        changed.chmod(0o644); changed.write_bytes(saved + b'\n')
        assert 'hash mismatch' in invoke('prepare', bm, success=False)
    finally:
        changed.write_bytes(saved); changed.chmod(mode)
    assert 'VERIFIED' in invoke('verify', bm)
    before = (a / 'Contents/MacOS/Seal').stat().st_ino
    bad_app = root / 'bad-app.json'; bad_app.write_text(json.dumps({**json.loads(am.read_text()), 'appArchiveSHA256': '0' * 64}))
    assert 'checksum mismatch' in invoke('install', bad_app, success=False)
    assert (a / 'Contents/MacOS/Seal').stat().st_ino == before
    builder.run('codesign', '--verify', '--deep', '--strict', a)
    config = dict(root=str(root), applicationA=str(a), applicationB=str(b), evidence=str(evidence))
    config_file = root / 'launch.json'; config_file.write_text(json.dumps(config))
    print(builder.run('node', HERE / 'test_launch.mjs', config_file))
    # The existing full signing/attributes/queue workflow runs against the installed shared app.
    env = {**os.environ, 'SEAL_PACKAGED_APP': str(a)}
    subprocess.run(['node', str(HERE.parent / 'tests/app.test.mjs')], env=env, check=True)
    shutil.rmtree(a)
    assert 'VERIFIED' in invoke('verify', bm)
    builder.run('codesign', '--verify', '--deep', '--strict', b)
    server.shutdown()
    assert 'REUSED' in invoke('prepare', bm), 'A valid runtime was not reused offline'
    manifest = json.loads((artifact / 'scripts/manifest.json').read_text())
    assert manifest['archiveURL'] == integration.PIN['archiveURL']
    assert manifest['runtimeID'] == integration.PIN['runtimeID']
    assert not list(artifact.glob('electron-*.zip'))
    report = dict(runtimeID=base['runtimeID'], sharedFiles=shared_files, runtimeDownloadsForTwoApps=1,
                  subsequentRuntimeDownloads=0, offlineReuse=True, runtimeChecksumRejection=True,
                  appChecksumPreservesExistingInstall=True, corruptCacheRejection=True, unsafeRootRejection=True,
                  strictSignatures=True, uninstallIsolation=True, twoAppLaunch=True, fullSealWorkflow=True,
                  noPerAppRuntimeArchive=True, privilegedInstallTested=False)
    (artifact / 'test-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
finally:
    server.shutdown(); server.server_close()
    shutil.rmtree(root)
