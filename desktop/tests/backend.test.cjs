const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { SealService, run, signArguments, parseSignature, classify, decodeXattr, commandText } = require('../backend.cjs');
const result = (status, stderr = '', stdout = '') => ({ status, stdout, stderr, succeeded: status === 0, timedOut: false });
test('classifies plugins, bundles and both Mach-O byte orders', () => {
  assert.equal(classify('/tmp/My Plug.component', true), 'plugin');
  assert.equal(classify('/tmp/App.app', true), 'app');
  assert.equal(classify('/tmp/lib', false, 'cffaedfe'), 'binary');
  assert.equal(classify('/tmp/code.class', false, 'cafebabe'), 'file');
  assert.equal(classify('/tmp/folder', true), 'folder');
});
test('ad-hoc signing omits timestamp, uses deep only for bundles and keeps paths as one argument', () => {
  const target = { path: "/tmp/space ' $(touch nope).vst3", kind: 'plugin' };
  const opts = { deep: true, preserveMetadata: true, timestamp: true, force: true };
  const args = signArguments(target, '-', opts, true);
  assert.deepEqual(args, ['--force', '--deep', '--preserve-metadata=entitlements,flags,runtime', '--sign', '-', target.path]);
  assert.ok(!signArguments({ ...target, kind: 'binary' }, '-', opts, false).includes('--deep'));
  assert.throws(() => signArguments(target, '--options', opts, false));
  assert.match(commandText('/usr/bin/codesign', args), /'\\''/);
});
test('certificate signing has explicit timestamp policy and entitlements', () => {
  const args = signArguments({ path: '/tmp/App.app', kind: 'app' }, 'A'.repeat(40), { timestamp: false, hardenedRuntime: true, entitlements: '/tmp/Entitlements File.plist' }, false);
  assert.deepEqual(args, ['--force', '--options', 'runtime', '--timestamp=none', '--entitlements', '/tmp/Entitlements File.plist', '--sign', 'A'.repeat(40), '/tmp/App.app']);
});
test('signature parser keeps verification and Gatekeeper assessment separate', () => {
  const text = 'Identifier=com.test\nFormat=app bundle\nSignature=adhoc\nTeamIdentifier=not set\nCDHash=abc\nCodeDirectory flags=0x10002(adhoc,runtime)';
  assert.equal(parseSignature(result(0, text), result(0)).status, 'adhoc');
  assert.equal(parseSignature(result(0, text), result(1)).status, 'invalid');
  assert.equal(parseSignature(result(1, 'code object is not signed at all'), result(1)).status, 'unsigned');
  assert.deepEqual(parseSignature(result(0, text), result(0)).flags, ['adhoc', 'runtime']);
});
test('quarantine decoder tolerates malformed and out-of-range dates', () => {
  const item = decodeXattr('com.apple.quarantine', Buffer.from('0081;671abcde;Safari;uuid').toString('hex'));
  assert.equal(item.quarantine.agent, 'Safari');
  assert.ok(item.quarantine.date.startsWith('2024'));
  assert.equal(decodeXattr('com.apple.quarantine', Buffer.from('0081;ffffffffffffffff;Safari;').toString('hex')).quarantine.date, '');
});
test('process runner retains stdout and stderr, bounds output and enforces timeout', async () => {
  const r = await run(process.execPath, ['-e', 'process.stdout.write("a".repeat(100));process.stderr.write("err")'], { maxOutput: 10 });
  assert.equal(r.stdout.length, 10); assert.equal(r.stderr, 'err'); assert.equal(r.truncated, true);
  const slow = await run('/bin/sleep', ['5'], { timeout: 30 });
  assert.equal(slow.timedOut, true); assert.equal(slow.succeeded, false);
  const missing = await run('/missing/seal-test', [], { timeout: 100 });
  assert.equal(missing.succeeded, false);
});
test('only explicitly selected paths are accepted, and replaced symlinks are rejected', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'seal-access-'));
  try {
    const file = path.join(dir, 'target'); await fs.writeFile(file, 'hello');
    const service = new SealService();
    await assert.rejects(service.target(file), /Choose this file/);
    const [target] = await service.adopt([file]); assert.equal(target.kind, 'file');
    await fs.rename(file, file + '-old'); await fs.symlink(file + '-old', file);
    await assert.rejects(service.target(target.path), /target changed/);
  } finally { await fs.rm(dir, { recursive: true, force: true }); }
});
test('real macOS signing, strict verification and recursive xattr cleanup on disposable bundles', { skip: process.platform !== 'darwin' }, async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'seal-sign-'));
  try {
    const bundle = path.join(dir, "Test ' $ Seal.vst3"), macos = path.join(bundle, 'Contents', 'MacOS');
    await fs.mkdir(macos, { recursive: true });
    await fs.writeFile(path.join(bundle, 'Contents', 'Info.plist'), '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.seal.test</string><key>CFBundleExecutable</key><string>test</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>');
    const src = path.join(dir, 'test.c'), binary = path.join(macos, 'test');
    await fs.writeFile(src, 'int main(void) { return 0; }');
    assert.equal((await run('/usr/bin/clang', [src, '-o', binary])).succeeded, true);
    await run('/usr/bin/xattr', ['-w', 'com.apple.quarantine', '0081;671abcde;SealTest;', bundle]);
    await run('/usr/bin/xattr', ['-w', 'com.apple.quarantine', '0081;671abcde;SealTest;', binary]);
    const service = new SealService(), [target] = await service.adopt([bundle]);
    await assert.rejects(service.sign(target.path, '-', { entitlements: '/not/chosen.plist' }), /Choose an entitlements/);
    const report = await service.sign(target.path, '-', { deep: true, force: true, removeQuarantine: true });
    assert.equal(report.signature.verified, true); assert.equal(report.signature.status, 'adhoc');
    assert.equal(report.xattrs.some((item) => item.quarantine), false);
    assert.equal((await run('/usr/bin/xattr', ['-p', 'com.apple.quarantine', binary])).succeeded, false);
    await run('/usr/bin/xattr', ['-w', 'com.seal.test', 'parent', bundle]);
    await run('/usr/bin/xattr', ['-w', 'com.seal.child', 'nested', binary]);
    const outside = path.join(dir, 'outside');
    await fs.writeFile(outside, 'untouched');
    await run('/usr/bin/xattr', ['-w', 'com.seal.external', 'keep', outside]);
    await fs.symlink(outside, path.join(bundle, 'outside-link'));
    await service.clearXattrs(target.path, true);
    assert.equal((await run('/usr/bin/xattr', ['-p', 'com.seal.external', outside])).stdout.trim(), 'keep');
    const remaining = (await run('/usr/bin/xattr', [binary])).stdout;
    assert.ok(!remaining.includes('com.seal.child'));
    assert.ok(!remaining.includes('com.apple.quarantine'));
    assert.ok(!(await service.inspect(target.path)).xattrs.some((item) => item.name === 'com.seal.test'));
    await fs.unlink(path.join(bundle, 'outside-link'));
    assert.equal((await service.inspect(target.path)).signature.verified, true);
  } finally { await fs.rm(dir, { recursive: true, force: true }); }
});
