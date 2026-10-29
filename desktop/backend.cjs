const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const TOOLS = Object.freeze({ codesign: '/usr/bin/codesign', xattr: '/usr/bin/xattr', security: '/usr/bin/security', spctl: '/usr/sbin/spctl', plutil: '/usr/bin/plutil', du: '/usr/bin/du' });
const BUNDLES = new Set(['app', 'framework', 'xpc', 'appex', 'bundle', 'plugin', 'kext', 'systemextension', 'qlgenerator', 'mdimporter']);
const PLUGINS = new Set(['vst3', 'vst', 'component', 'aaxplugin']);
const quote = (s) => /^[\w./:=@-]+$/.test(s) ? s : "'" + s.replaceAll("'", "'\\''") + "'";
const commandText = (tool, args) => [tool, ...args].map(quote).join(' ');

// Fixed executable paths and argument arrays; no shell. Bound output and tool lifetime.
function run(tool, args, { timeout = 180000, input, onCommand, maxOutput = 2000000 } = {}) {
  onCommand?.(commandText(tool, args));
  return new Promise((resolve) => {
    let child, stdout = [], stderr = [], outSize = 0, errSize = 0, timedOut = false, truncated = false;
    try { child = spawn(tool, args, { env: { ...process.env, LC_ALL: 'C', LANG: 'C' }, stdio: ['pipe', 'pipe', 'pipe'] }); }
    catch (error) { resolve({ status: -1, stdout: '', stderr: error.message, timedOut: false, succeeded: false }); return; }
    const capture = (chunks, current, chunk) => {
      if (current < maxOutput) chunks.push(chunk.subarray(0, maxOutput - current));
      if (current + chunk.length > maxOutput) truncated = true;
      return current + chunk.length;
    };
    child.stdout.on('data', (data) => { outSize = capture(stdout, outSize, data); });
    child.stderr.on('data', (data) => { errSize = capture(stderr, errSize, data); });
    let kill;
    const timer = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); kill = setTimeout(() => child.kill('SIGKILL'), 1500); }, timeout);
    child.on('error', (error) => stderr.push(Buffer.from(error.message)));
    child.on('close', (status) => {
      clearTimeout(timer); clearTimeout(kill);
      resolve({ status: status ?? -1, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8'), timedOut, truncated, succeeded: status === 0 && !timedOut });
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}
const combined = (r) => [r.stdout.trim(), r.stderr.trim(), r.timedOut ? 'Operation timed out.' : ''].filter(Boolean).join('\n');
function classify(filePath, directory, magic = '') {
  const ext = path.extname(filePath).slice(1).toLowerCase();
  if (directory) return ext === 'app' ? 'app' : PLUGINS.has(ext) ? 'plugin' : BUNDLES.has(ext) ? 'bundle' : 'folder';
  return ['feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'cafebabf', 'bebafeca', 'bfbafeca'].includes(magic) && ext !== 'class' ? 'binary' : 'file';
}
function parseSignature(display, verification) {
  const text = combined(display);
  const report = { status: 'unsigned', exists: display.succeeded, verified: verification.succeeded, raw: text, verificationOutput: combined(verification), authorities: [], flags: [], entitlements: '', gatekeeper: { status: 'notAssessed', output: '' } };
  for (const line of text.split('\n')) {
    const entry = line.match(/^(Identifier|Format|TeamIdentifier|CDHash|Timestamp|Authority)=(.*)$/);
    if (entry) {
      const [, key, value] = entry;
      if (key === 'Authority') report.authorities.push(value);
      else report[{ Identifier: 'identifier', Format: 'format', TeamIdentifier: 'teamID', CDHash: 'cdhash', Timestamp: 'timestamp' }[key]] = value;
    }
    const flags = line.match(/flags=0x[\da-f]+\(([^)]+)\)/i);
    if (flags) report.flags = flags[1].split(',');
  }
  report.status = !display.succeeded ? (/not signed at all|code object is not signed/i.test(text) ? 'unsigned' : 'invalid') : !verification.succeeded ? 'invalid' : /Signature=adhoc/i.test(text) ? 'adhoc' : 'signed';
  return report;
}
function signArguments(target, identity, options, existing) {
  if (!(identity === '-' || /^[\da-f]{40}$/i.test(identity))) throw new Error('Invalid signing identity.');
  const args = [];
  if (options.force !== false) args.push('--force');
  if (options.deep && ['app', 'plugin', 'bundle'].includes(target.kind)) args.push('--deep');
  if (options.preserveMetadata && existing) args.push('--preserve-metadata=entitlements,flags,runtime');
  if (options.hardenedRuntime) args.push('--options', 'runtime');
  if (identity !== '-') args.push(options.timestamp ? '--timestamp' : '--timestamp=none');
  if (options.entitlements) args.push('--entitlements', options.entitlements);
  args.push('--sign', identity, target.path);
  return args;
}
function decodeXattr(name, hex) {
  const data = Buffer.from(hex.replace(/\s/g, ''), 'hex'), text = data.toString('utf8');
  const item = { name, size: data.length, hex: data.subarray(0, 4096).toString('hex'), summary: '', details: [] };
  if (name === 'com.apple.quarantine') {
    const [flags, timestamp, agent, origin] = text.split(';'), seconds = parseInt(timestamp, 16);
    item.quarantine = { flags, agent: agent || '', date: Number.isFinite(seconds) && !Number.isNaN(new Date(seconds * 1000).getTime()) ? new Date(seconds * 1000).toISOString() : '', origin: origin || '' };
    item.summary = agent || text; item.details = [text];
  } else if (!text.includes('\uFFFD') && !/[\x00-\x08\x0e-\x1f]/.test(text)) {
    item.summary = text.slice(0, 180); item.details = [text.slice(0, 4096)];
  } else item.summary = data.subarray(0, 20).toString('hex');
  return item;
}
class SealService {
  constructor(onCommand = () => {}) { this.allowed = new Set(); this.entitlements = new Set(); this.onCommand = onCommand; this.mutating = false; }
  command(name, args, options = {}) { return run(TOOLS[name], args, { onCommand: this.onCommand, ...options }); }
  async adopt(paths) {
    if (!Array.isArray(paths) || paths.length > 1000) throw new Error('Invalid file selection.');
    const adopted = [];
    for (const entry of paths) {
      if (typeof entry !== 'string' || !path.isAbsolute(entry) || entry.includes('\0')) throw new Error('Invalid target path.');
      const canonical = await fs.realpath(entry);
      this.allowed.add(canonical); adopted.push(await this.target(canonical));
    }
    return [...new Map(adopted.map((item) => [item.path, item])).values()];
  }
  async target(filePath) {
    if (typeof filePath !== 'string' || !this.allowed.has(filePath)) throw new Error('Choose this file in Seal before operating on it.');
    if (await fs.realpath(filePath) !== filePath) throw new Error('The selected target changed. Choose it again.');
    const stat = await fs.lstat(filePath);
    if (!stat.isDirectory() && !stat.isFile()) throw new Error('Select a regular file or code bundle.');
    let magic = '';
    if (stat.isFile()) {
      const file = await fs.open(filePath, 'r');
      try { const buffer = Buffer.alloc(4); await file.read(buffer, 0, 4, 0); magic = buffer.toString('hex'); } finally { await file.close(); }
    }
    const kind = classify(filePath, stat.isDirectory(), magic);
    let writable = true;
    try { await fs.access(filePath, require('node:fs').constants.W_OK); } catch { writable = false; }
    return { path: filePath, name: path.basename(filePath), kind, directory: stat.isDirectory(), size: stat.isFile() ? stat.size : null, modified: stat.mtime.toISOString(), canSign: kind !== 'folder', writable };
  }
  async inspect(filePath) {
    const target = await this.target(filePath);
    const signatureTask = this.inspectSignature(target);
    const xattrTask = this.listXattrs(filePath).catch((error) => ({ error: error.message, items: [] }));
    const sizeTask = target.directory ? this.command('du', ['-sk', filePath], { timeout: 12000 }).then((r) => r.succeeded ? parseInt(r.stdout, 10) * 1024 : null) : Promise.resolve(target.size);
    const [signature, attributes, size] = await Promise.all([signatureTask, xattrTask, sizeTask]);
    return { target: { ...target, size }, signature, xattrs: attributes.items, xattrError: attributes.error || '' };
  }
  async inspectSignature(target) {
    if (!target.canSign) return { status: 'unsupported', exists: false, verified: false, authorities: [], flags: [], gatekeeper: { status: 'notAssessed', output: '' }, verificationOutput: '', entitlements: '', raw: '' };
    const [display, verification] = await Promise.all([this.command('codesign', ['-dvvv', target.path]), this.command('codesign', ['--verify', '--deep', '--strict', '--verbose=2', target.path])]);
    const report = parseSignature(display, verification);
    if (!display.succeeded) return report;
    const [entitlements, gatekeeper] = await Promise.all([this.command('codesign', ['-d', '--entitlements', ':-', target.path]), target.kind === 'app' ? this.command('spctl', ['--assess', '--type', 'execute', '--verbose=4', target.path], { timeout: 30000 }) : null]);
    const xml = entitlements.stdout || entitlements.stderr;
    report.entitlements = xml.includes('<?xml') ? xml.slice(xml.indexOf('<?xml')).trim() : xml.includes('<plist') ? xml.slice(xml.indexOf('<plist')).trim() : '';
    if (gatekeeper) report.gatekeeper = { status: gatekeeper.succeeded ? 'accepted' : 'rejected', output: combined(gatekeeper) };
    return report;
  }
  async identities() {
    const result = await this.command('security', ['find-identity', '-v', '-p', 'codesigning']);
    const identities = [{ id: '-', name: 'Ad-hoc', adHoc: true }];
    for (const line of combined(result).split('\n')) { const match = line.match(/^\s*\d+\)\s+([\da-f]{40})\s+"(.*)"\s*$/i); if (match) identities.push({ id: match[1], name: match[2], adHoc: false }); }
    return { identities, error: result.succeeded ? '' : combined(result) };
  }
  async listXattrs(filePath) {
    const list = await this.command('xattr', [filePath]);
    if (!list.succeeded) throw new Error(combined(list));
    const items = [];
    for (const name of list.stdout.split('\n').filter(Boolean)) {
      const value = await this.command('xattr', ['-px', name, filePath]);
      if (!value.succeeded) throw new Error(combined(value));
      const item = decodeXattr(name, value.stdout); item.truncated = value.truncated;
      if (name === 'com.apple.metadata:kMDItemWhereFroms' && !value.truncated) {
        const plist = await this.command('plutil', ['-convert', 'json', '-o', '-', '--', '-'], { input: Buffer.from(value.stdout.replace(/\s/g, ''), 'hex') });
        if (plist.succeeded) { try { const parsed = JSON.parse(plist.stdout); if (Array.isArray(parsed) && parsed.every((entry) => typeof entry === 'string')) { item.details = parsed; item.summary = parsed[0] || ''; } } catch {} }
      }
      items.push(item);
    }
    return { items: items.sort((a, b) => a.name === 'com.apple.quarantine' ? -1 : b.name === 'com.apple.quarantine' ? 1 : a.name.localeCompare(b.name)) };
  }
  async withMutation(fn) { if (this.mutating) throw new Error('Another file operation is running.'); this.mutating = true; try { return await fn(); } finally { this.mutating = false; } }
  async sign(filePath, identity, options = {}) {
    return this.withMutation(async () => {
      const target = await this.target(filePath);
      if (!target.canSign) throw new Error('Ordinary folders cannot be signed.');
      if (!target.writable) throw new Error('The target is read-only. Copy it to a writable location.');
      if (options.entitlements && !this.entitlements.has(options.entitlements)) throw new Error('Choose an entitlements file in Seal first.');
      if (options.entitlements) await fs.access(options.entitlements);
      const before = await this.inspectSignature(target);
      const result = await this.command('codesign', signArguments(target, identity, options, before.exists));
      if (!result.succeeded) throw new Error(combined(result) || `codesign failed (${result.status}).`);
      let warning = '';
      if (options.removeQuarantine) {
        const removed = await this.command('xattr', ['-drs', 'com.apple.quarantine', filePath]);
        if (!removed.succeeded && !/No such xattr/i.test(combined(removed))) warning = combined(removed);
      }
      const report = await this.inspect(filePath);
      if (!report.signature.verified) throw new Error(report.signature.verificationOutput || 'Signature verification failed after signing.');
      return { ...report, warning };
    });
  }
  async removeXattr(filePath, name, recursive = false) {
    return this.withMutation(async () => {
      await this.target(filePath);
      if (typeof name !== 'string' || !name || name.startsWith('-') || name.includes('\0')) throw new Error('Invalid attribute name.');
      const result = await this.command('xattr', [recursive ? '-drs' : '-ds', name, filePath]);
      if (!result.succeeded && !/No such xattr/i.test(combined(result))) throw new Error(combined(result));
      return this.inspect(filePath);
    });
  }
  async clearXattrs(filePath, recursive) {
    return this.withMutation(async () => {
      await this.target(filePath);
      const result = await this.command('xattr', [recursive ? '-crs' : '-cs', filePath]);
      if (!result.succeeded) throw new Error(combined(result));
      return this.inspect(filePath);
    });
  }
}
module.exports = { SealService, run, combined, classify, signArguments, parseSignature, decodeXattr, commandText };
