import { _electron as electron, expect } from '@playwright/test';
import { mkdtemp, writeFile, mkdir, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { lensDisplayPoint } from '../src/vendor/crt.js';
const require = createRequire(import.meta.url);
const { run, SealService } = require('../backend.cjs');
const desktop = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const scratch = await mkdtemp(path.join(tmpdir(), 'seal-ui-'));
const screenshots = path.resolve(desktop, '../dist/qa');
await mkdir(screenshots, { recursive: true });
let app;
const errors = [];
try {
  const source = path.join(scratch, 'test.c'), binary = path.join(scratch, "Test ' & Seal"), second = path.join(scratch, 'Second target'), dropped = path.join(scratch, 'Dropped target');
  await writeFile(source, 'int main(void) { return 0; }');
  const compile = await run('/usr/bin/clang', [source, '-o', binary]);
  if (!compile.succeeded) throw new Error(compile.stderr);
  await copyFile(binary, second);
  await copyFile(binary, dropped);
  await run('/usr/bin/xattr', ['-w', 'com.apple.quarantine', '0081;671abcde;SealTest;test-origin', binary]);
  await run('/usr/bin/xattr', ['-w', 'com.seal.fixture', '<img src=x onerror=alert(1)>', binary]);
  const packaged = process.env.SEAL_PACKAGED_APP;
  app = await electron.launch({ ...(packaged ? { executablePath: path.join(packaged, 'Contents/MacOS/Seal') } : {}), args: packaged ? ['--inspect', binary] : [desktop, '--inspect', binary], env: { ...process.env, SEAL_TEST_USER_DATA: path.join(scratch, 'preferences'), ELECTRON_ENABLE_LOGGING: '1' } });
  const page = await app.firstWindow();
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (msg) => { if (msg.type() === 'error') console.error('Renderer:', msg.text()); });
  await page.waitForFunction(() => document.querySelector('#start')?.textContent.trim());
  await page.waitForFunction(() => !!document.querySelector('.file-meta'));
  // Exercise the physical pointer through the same quantized CRT inverse as the renderer.
  async function click(selector) {
    const locator = page.locator(`${selector}:visible`).first();
    await locator.scrollIntoViewIfNeeded();
    await expect(locator).toBeEnabled();
    const rect = await locator.boundingBox();
    const geometry = await page.evaluate(() => ({ crt: document.documentElement.classList.contains('crt-mode'), w: document.querySelector('.crt-surface').clientWidth, h: innerHeight }));
    const point = geometry.crt ? lensDisplayPoint(rect.x + rect.width / 2, rect.y + rect.height / 2, geometry.w, geometry.h) : { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
    await page.mouse.click(point.x, point.y);
  }
  await page.screenshot({ path: path.join(screenshots, 'welcome.png') });
  await click('#start');
  await page.waitForFunction(() => document.querySelector('#welcome').hidden && !document.body.classList.contains('portal-opening'));
  await expect(page.locator('.file-meta h2')).toContainText("Test ' & Seal");
  await expect(page.locator('[data-action="sign"]').first()).toBeEnabled();
  await page.screenshot({ path: path.join(screenshots, 'inspect-before.png') });
  // Signing mutates only the temporary fixture, then verifies it through the real backend.
  await click('[data-action="sign"]');
  await expect(page.locator('.signature-panel .signature-badge')).toHaveClass(/adhoc/);
  await expect(page.locator('[data-action="sign"]').first()).toBeEnabled();
  const check = new SealService(); const [target] = await check.adopt([binary]);
  expect((await check.inspect(target.path)).signature.verified).toBe(true);
  expect((await run('/usr/bin/xattr', ['-p', 'com.apple.quarantine', binary])).succeeded).toBe(false);
  await page.evaluate(() => { document.querySelector('#main').scrollTop = 0; });
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(screenshots, 'inspect-signed.png') });
  await click('[data-page="attributes"]');
  await page.waitForFunction(() => document.querySelector('#site').dataset.view === 'attributes' && !document.querySelector('#main').inert);
  await expect(page.locator('.xattr-row').filter({ hasText: 'com.seal.fixture' })).toHaveCount(1);
  expect(await page.locator('.xattr-row img').count()).toBe(0);
  await click('[data-action="remove-xattr"][data-name="com.seal.fixture"]');
  await expect(page.locator('.xattr-row').filter({ hasText: 'com.seal.fixture' })).toHaveCount(0);
  // Open a genuine OS File from the renderer; the sandboxed preload extracts its path.
  await app.evaluate(({ dialog }, filePath) => {
    dialog.showOpenDialog = async () => ({ canceled: false, filePaths: filePath });
  }, [second, binary]);
  await click('[data-page="batch"]');
  await page.waitForFunction(() => document.querySelector('#site').dataset.view === 'batch' && !document.querySelector('#main').inert);
  await click('#batch-add');
  await expect(page.locator('.queue-row')).toHaveCount(2);
  await expect(page.locator('#batch-sign')).toBeEnabled();
  // A real File provided by Chromium carries the OS path across the sandbox bridge.
  await page.evaluate(() => { const input = document.createElement('input'); input.type = 'file'; input.id = 'drop-fixture'; input.hidden = true; document.body.append(input); });
  await page.locator('#drop-fixture').setInputFiles(dropped);
  await page.evaluate(() => { const transfer = new DataTransfer(); transfer.items.add(document.querySelector('#drop-fixture').files[0]); document.dispatchEvent(new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true })); });
  await expect(page.locator('.queue-row')).toHaveCount(3);
  await expect(page.locator('#batch-sign')).toBeEnabled();
  await click('#batch-sign');
  await expect(page.locator('.queue-row')).toHaveClass([/signed/, /signed/, /signed/]);
  await expect(page.locator('#batch-sign')).toBeEnabled();
  await page.screenshot({ path: path.join(screenshots, 'batch.png') });
  await click('#system-open');
  await page.waitForFunction(() => document.querySelector('#system-dialog').open && !document.querySelector('.system-content').inert);
  await click('[data-language="en"]');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await page.waitForFunction(() => !document.querySelector('.ascii-scramble'));
  await click('[data-appearance-choice="light"]');
  await expect(page.locator('html')).toHaveAttribute('data-appearance', 'light');
  await page.waitForTimeout(550);
  await page.screenshot({ path: path.join(screenshots, 'settings-light-en.png') });
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('#system-dialog').open);
  await click('[data-page="overview"]');
  await page.waitForFunction(() => document.querySelector('#site').dataset.view === 'overview' && !document.querySelector('#main').inert);
  await page.screenshot({ path: path.join(screenshots, 'inspect-light-en.png') });
  // Resize the real app to its supported minimum and check horizontal containment.
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(960, 680));
  await page.waitForTimeout(500);
  const overflow = await page.evaluate(() => ({ main: document.querySelector('#main').scrollWidth > document.querySelector('#main').clientWidth + 1, body: document.body.scrollWidth > innerWidth }));
  expect(overflow).toEqual({ main: false, body: false });
  await page.screenshot({ path: path.join(screenshots, 'compact-light-en.png') });
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1180, 820));
  await page.keyboard.press('Meta+,');
  await page.waitForFunction(() => document.querySelector('#system-dialog').open && !document.querySelector('.system-content').inert);
  await click('[data-language="zh"]');
  await click('[data-appearance-choice="dark"]');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('#system-dialog').open);
  await page.evaluate(() => { document.querySelector('#main').scrollTop = 0; });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(screenshots, 'inspect-dark-zh.png') });
  expect(errors).toEqual([]);
  console.log('PASS: native Electron launch, native file selection + real-file drop bridge, CRT pointer mapping, onboarding, signature inspection, real signing + strict verification, recursive quarantine cleanup, safe xattr rendering + removal, batch signing, settings, English, light appearance and compact layout.');
  console.log('Screenshots:', screenshots);
} finally {
  if (app) await app.close();
  await rm(scratch, { recursive: true, force: true });
}
