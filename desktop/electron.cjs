const { app, BrowserWindow, Menu, ipcMain, dialog, shell, clipboard, screen } = require('electron');
const path = require('node:path');
const fs = require('node:fs/promises');
const { SealService, run, signArguments, commandText } = require('./backend.cjs');
app.setName('Seal');
if (process.env.SEAL_TEST_USER_DATA) app.setPath('userData', process.env.SEAL_TEST_USER_DATA);
let window, pendingPaths = [];
const service = new SealService((command) => { if (window && !window.isDestroyed()) window.webContents.send('seal:command', command); });
const PRESETS = { compact: [1040, 720], standard: [1180, 820], large: [1380, 920] };
function resize(preset) {
  if (!PRESETS[preset]) throw new Error('Invalid window preset.');
  const area = screen.getDisplayMatching(window.getBounds()).workArea;
  window.setSize(Math.min(PRESETS[preset][0], area.width), Math.min(PRESETS[preset][1], area.height));
  window.center();
}
async function migrateSettings() {
  const language = await run('/usr/bin/defaults', ['read', 'com.andyyu.seal', 'app.language'], { timeout: 3000 });
  const preset = await run('/usr/bin/defaults', ['read', 'com.andyyu.seal', 'window.preset'], { timeout: 3000 });
  return { language: language.succeeded ? language.stdout.trim() === 'en' ? 'en' : 'zh' : null, preset: preset.succeeded ? preset.stdout.trim() : null };
}
const handlers = {
  async initialState() { const paths = pendingPaths; pendingPaths = []; return { targets: await service.adopt(paths), migrated: await migrateSettings(), version: app.getVersion() }; },
  async chooseTargets() {
    const result = await dialog.showOpenDialog(window, { properties: ['openFile', 'openDirectory', 'multiSelections'], buttonLabel: 'Open / 打开' });
    return result.canceled ? [] : service.adopt(result.filePaths);
  },
  adopt: (paths) => service.adopt(paths),
  inspect: (filePath) => service.inspect(filePath),
  async preview(filePath, identity, options, existing) { const target = await service.target(filePath); return commandText('/usr/bin/codesign', signArguments(target, identity, options, existing === true)); },
  identities: () => service.identities(),
  sign: (filePath, identity, options) => service.sign(filePath, identity, options),
  async chooseEntitlements() {
    const result = await dialog.showOpenDialog(window, { properties: ['openFile'], filters: [{ name: 'Entitlements', extensions: ['plist', 'entitlements'] }] });
    if (result.canceled) return null;
    const filePath = await fs.realpath(result.filePaths[0]);
    const check = await service.command('plutil', ['-lint', filePath]);
    if (!check.succeeded) throw new Error('Select a valid property list / 请选择有效的 plist 文件。');
    service.entitlements.add(filePath);
    return filePath;
  },
  removeXattr: (filePath, name, recursive) => service.removeXattr(filePath, name, recursive === true),
  async clearXattrs(filePath, recursive) {
    const target = await service.target(filePath);
    const result = await dialog.showMessageBox(window, { type: 'warning', message: 'Clear extended attributes? / 清除扩展属性？', detail: `${target.path}\n${recursive ? 'Includes nested files / 包含嵌套文件' : 'Top level only / 仅顶层'}\nThis cannot be undone. / 此操作无法撤销。`, buttons: ['Cancel / 取消', 'Clear / 清除'], defaultId: 0, cancelId: 0 });
    return result.response === 1 ? service.clearXattrs(filePath, recursive === true) : null;
  },
  async reveal(filePath) { await service.target(filePath); shell.showItemInFolder(filePath); },
  copy(text) { if (typeof text !== 'string' || text.length > 4000000) throw new Error('Invalid clipboard content.'); clipboard.writeText(text); },
  resize,
};
ipcMain.handle('seal:invoke', async (event, action, ...args) => {
  try {
    if (event.sender !== window?.webContents || event.senderFrame !== window.webContents.mainFrame || !Object.hasOwn(handlers, action)) throw new Error('Unsupported operation.');
    return { ok: true, value: await handlers[action](...args) };
  } catch (error) { return { ok: false, error: error.message }; }
});
app.on('open-file', (event, filePath) => {
  event.preventDefault();
  if (window?.webContents.isLoading() === false) service.adopt([filePath]).then((targets) => window.webContents.send('seal:open', targets)).catch(() => {});
  else pendingPaths.push(filePath);
});
function createWindow() {
  window = new BrowserWindow({ width: 1180, height: 820, minWidth: 960, minHeight: 680, title: 'Seal', titleBarStyle: 'hiddenInset', backgroundColor: '#080808', show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, autoplayPolicy: 'no-user-gesture-required' } });
  window.once('ready-to-show', () => window.show());
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event) => event.preventDefault());
  window.on('close', (event) => {
    if (service.mutating) { event.preventDefault(); dialog.showMessageBox(window, { message: 'Wait for the current file operation to finish. / 请等待当前文件操作完成。' }); }
  });
  if (!app.isPackaged && process.env.SEAL_DEV_URL === 'http://127.0.0.1:1420') window.loadURL(process.env.SEAL_DEV_URL);
  else window.loadFile(path.join(__dirname, 'dist', 'index.html'));
}
app.whenReady().then(() => {
  for (let i = 1; i < process.argv.length; i++) if (['--inspect', '--batch'].includes(process.argv[i]) && process.argv[i + 1]) pendingPaths.push(process.argv[++i]);
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'Seal', submenu: [{ role: 'about' }, { label: 'Settings / 设置…', accelerator: 'CmdOrCtrl+,', click: () => window?.webContents.send('seal:menu', 'settings') }, { type: 'separator' }, { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' }, { role: 'quit' }] },
    { label: 'File / 文件', submenu: [{ label: 'Open / 打开…', accelerator: 'CmdOrCtrl+O', click: () => window?.webContents.send('seal:menu', 'open') }, { label: 'Refresh / 刷新', accelerator: 'CmdOrCtrl+R', click: () => window?.webContents.send('seal:menu', 'refresh') }, { label: 'Re-sign / 重新签名', accelerator: 'CmdOrCtrl+Shift+Enter', click: () => window?.webContents.send('seal:menu', 'sign') }, { role: 'close' }] },
    { role: 'editMenu' }, { role: 'windowMenu' },
  ]));
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => app.quit());
