import { _electron } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const apps = [], profiles = [];
try {
  for (const [index, bundle] of [config.applicationA, config.applicationB].entries()) {
    const profile = path.join(config.root, 'profiles', String(index));
    const app = await _electron.launch({ executablePath: path.join(bundle, 'Contents/MacOS/Seal'),
      env: { ...process.env, SEAL_TEST_USER_DATA: profile } });
    apps.push(app);
    const page = await app.firstWindow();
    await page.waitForSelector('#start');
    assert.equal(await page.evaluate(() => typeof require), 'undefined');
    const details = await app.evaluate(({ app, BrowserWindow }) => ({ profile: app.getPath('userData'), pid: process.pid,
      sandbox: BrowserWindow.getAllWindows()[0].webContents.getLastWebPreferences().sandbox,
      isolation: BrowserWindow.getAllWindows()[0].webContents.getLastWebPreferences().contextIsolation,
      noSandbox: app.commandLine.hasSwitch('no-sandbox'), version: app.getVersion() }));
    assert.equal(details.sandbox, true); assert.equal(details.isolation, true); assert.equal(details.noSandbox, false);
    assert.equal(details.profile, profile); profiles.push(details.profile);
    await page.screenshot({ path: path.join(config.evidence, `shared-app-${index + 1}.png`) });
    console.log(JSON.stringify(details));
  }
  assert.notEqual(apps[0].process().pid, apps[1].process().pid);
  assert.notEqual(profiles[0], profiles[1]);
  await apps[0].close();
  assert.equal(await (await apps[1].firstWindow()).title(), 'Seal');
  console.log('Separate processes/profiles, sandbox, context isolation and independent quit: PASS');
} finally {
  for (const app of apps) { try { await app.close(); } catch {} }
}
