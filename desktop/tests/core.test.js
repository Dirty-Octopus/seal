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
