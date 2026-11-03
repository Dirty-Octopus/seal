import test from "node:test";
import assert from "node:assert/strict";
import { lensSourcePoint, lensDisplayPoint } from "../src/vendor/crt.js";
import { sanitize, loadPreferences, defaults } from "../src/preferences.js";
test("quantized SVG displacement has an accurate inverse at edges and center", () => {
  for (const [w, h] of [
    [1180, 820],
    [860, 640],
    [1440, 900],
  ])
    for (const x of [30, w / 2, w - 30])
      for (const y of [40, h / 2, h - 24]) {
        const d = lensDisplayPoint(x, y, w, h),
          s = lensSourcePoint(d.x, d.y, w, h);
        assert.ok(Math.hypot(s.x - x, s.y - y) < 0.05);
        assert.ok(d.x >= 0 && d.x <= w && d.y >= 0 && d.y <= h);
      }
});
test("invalid persisted settings cannot inject values or NaN into rendering", () => {
  assert.deepEqual(
    sanitize({
      treatment: "invalid",
      softness: NaN,
      motion: "false",
      language: "x",
    }),
    defaults,
  );
  assert.equal(sanitize({ softness: 9 }).softness, 0.8);
  assert.deepEqual(loadPreferences({ getItem: () => "{broken" }), defaults);
});
import { resolveAppearance } from "../src/appearance.js";
test("appearance defaults to system and explicit modes ignore system changes", () => {
  assert.equal(sanitize({}).appearance, "system");
  assert.equal(sanitize({ appearance: "invalid" }).appearance, "system");
  assert.equal(resolveAppearance("system", true), "dark");
  assert.equal(resolveAppearance("system", false), "light");
  assert.equal(resolveAppearance("light", true), "light");
  assert.equal(resolveAppearance("dark", false), "dark");
});
import { defaultCrtEnabled, loadCrtPreference } from '../src/preferences.js';
test('fresh and invalid preferences default to zero softness and CRT off', () => {
  assert.equal(defaults.softness, 0);
  assert.equal(defaultCrtEnabled, false);
  assert.equal(loadPreferences({ getItem: () => null }).softness, 0);
  assert.equal(sanitize({ softness: NaN }).softness, 0);
  assert.equal(loadCrtPreference({ getItem: () => null }), false);
  assert.equal(loadCrtPreference({ getItem: () => 'invalid' }), false);
  assert.equal(loadCrtPreference({ getItem: () => { throw new Error('Storage unavailable'); } }), false);
});
test('explicit saved softness and CRT choices survive the new defaults', () => {
  assert.equal(sanitize({ softness: 0.2 }).softness, 0.2);
  assert.equal(sanitize({ softness: 0 }).softness, 0);
  assert.equal(loadCrtPreference({ getItem: () => 'true' }), true);
  assert.equal(loadCrtPreference({ getItem: () => 'false' }), false);
});
