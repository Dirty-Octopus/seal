import "@fontsource/barlow-condensed/latin-500.css";
import "@fontsource/barlow-condensed/latin-600.css";
import "@fontsource/ibm-plex-mono/latin-400.css";
import "./style.css";
import "./vendor/reference.css";
import "./replica.css";
import "./appearance.css";
import "./seal.css";
import { initSeal } from "./seal.js";
import { initAppearance } from "./appearance.js";
import { initLanguageLayout, reserveLanguageSpace } from "./language-layout.js";
import { clearScramble, scrambleText } from "./vendor/text-transition.js";
import { initBackground } from "./vendor/background.js";
import { initScroll, initNoise } from "./vendor/tactile.js";
import { changeView, initPageMotion } from "./vendor/interface.js";
import { runAssembly } from "./vendor/portal-assembly.js";

import { initCrtLens } from "./vendor/crt.js";
import { initSettings } from "./vendor/settings.js";
import { initWelcome } from "./ambient.js";
import { defaults, loadPreferences } from "./preferences.js";
const $ = (s) => document.querySelector(s),
  $$ = (s) => [...document.querySelectorAll(s)];
let prefs = loadPreferences(localStorage);
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const motionAllowed = () => prefs.motion && !reduced.matches;
const t = (zh, en) => (prefs.language === "zh" ? zh : en);
function save() {
  localStorage.setItem("seal-interface", JSON.stringify(prefs));
}
let appearance;
function sync() {
  document.body.dataset.treatment = prefs.treatment;
  document.body.classList.toggle("motion-off", !motionAllowed());
  document.documentElement.classList.toggle("no-motion", !motionAllowed());
  document.documentElement.lang = prefs.language === "zh" ? "zh-CN" : "en";
  document.documentElement.style.setProperty(
    "--screen-softness",
    `${prefs.softness}px`,
  );
  $("#softness").value = prefs.softness;
  $("#softness-value").value = prefs.softness.toFixed(2);
  $$("[data-zh]").forEach(
    (el) => (el.textContent = el.dataset[prefs.language]),
  );
  for (const key of ["motion", "sound"]) {
    const b = $(`#${key}-toggle`);
    b.textContent = prefs[key] ? "ON" : "OFF";
    b.setAttribute("aria-checked", String(prefs[key]));
  }
  $$("button[data-treatment]").forEach((b) =>
    b.setAttribute(
      "aria-pressed",
      String(b.dataset.treatment === prefs.treatment),
    ),
  );
  $$("[data-language]").forEach((b) =>
    b.setAttribute(
      "aria-pressed",
      String(b.dataset.language === prefs.language),
    ),
  );
  reserveLanguageSpace();
  appearance?.apply();
  document.dispatchEvent(new Event("languagechange"));
  document.dispatchEvent(new Event("motionchange"));
}
const voices = new Map();
function sound(name, volume = 0.19) {
  if (!prefs.sound) return;
  try {
    let pool = voices.get(name);
    if (!pool) {
      pool = Array.from(
        { length: 4 },
        () => new Audio(new URL(`sounds/${name}.wav`, document.baseURI).href),
      );
      voices.set(name, pool);
    }
    const a = pool.find((a) => a.paused) || pool[0];
    a.currentTime = 0;
    a.volume = volume;
    a.play().catch(() => {});
  } catch {}
}
const interactive =
  'button,a[href],input,textarea,select,[role="button"],[role="switch"],[role="slider"],[tabindex]:not([tabindex="-1"])';
let lastPreselect = { control: null, time: 0 };
function controlAt(target) {
  const c = target.closest?.(interactive);
  return c &&
    !c.disabled &&
    c.getAttribute("aria-disabled") !== "true" &&
    !c.closest("[inert]")
    ? c
    : null;
}
function preselect(event) {
  const control = controlAt(event.target);
  if (!control) return;
  if (
    event.type === "pointerover" &&
    (event.pointerType !== "mouse" || control.contains(event.relatedTarget))
  )
    return;
  const now = performance.now();
  if (control === lastPreselect.control && now - lastPreselect.time < 30)
    return;
  lastPreselect = { control, time: now };
  sound("preselect", 0.15);
}
document.addEventListener("pointerover", preselect);
document.addEventListener("focusin", preselect);
// Capture before an action disables or replaces its own control.
document.addEventListener(
  "click",
  (event) => {
    if (controlAt(event.target)) sound("clickevent", 0.19);
  },
  true,
);
$$("button[data-treatment]").forEach(
  (b) =>
    (b.onclick = () => {
      prefs.treatment = b.dataset.treatment;
      save();
      sync();
    }),
);
$$("[data-language]").forEach(
  (b) =>
    (b.onclick = () => {
      if (prefs.language === b.dataset.language) return;
      clearScramble();
      reserveLanguageSpace();
      prefs.language = b.dataset.language;
      save();
      sync();
      if (!document.body.classList.contains("boot-visible")) scrambleText();
    }),
);
for (const key of ["motion", "sound"])
  $(`#${key}-toggle`).onclick = () => {
    prefs[key] = !prefs[key];
    if (key === "sound" && !prefs.sound)
      for (const pool of voices.values()) for (const a of pool) a.pause();
    save();
    sync();
  };
$("#softness").oninput = (e) => {
  prefs.softness = Number(e.target.value);
  document.documentElement.style.setProperty(
    "--screen-softness",
    `${prefs.softness}px`,
  );
  $("#softness-value").value = prefs.softness.toFixed(2);
  save();
};
$("#reset").onclick = () => {
  prefs = { ...defaults };
  save();
  sync();
  document.dispatchEvent(new Event("settingsreset"));
};
reduced.addEventListener("change", sync);
sync();
initCrtLens(t);
initSettings({
  motionAllowed,
  onOpen: () => requestAnimationFrame(reserveLanguageSpace),
});
initBackground(motionAllowed);
appearance = initAppearance({
  getPreference: () => prefs.appearance,
  motionAllowed,
});
initLanguageLayout();
$$("[data-appearance-choice]").forEach(
  (b) =>
    (b.onclick = () => {
      prefs.appearance = b.dataset.appearanceChoice;
      save();
      appearance.apply();
    }),
);
initNoise(motionAllowed);
initPageMotion({ sfx: (name) => sound(name, 0.2) });
initScroll({ sfx: (name) => sound(name, 0.12) }, motionAllowed);

document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === ",") {
    e.preventDefault();
    if (!$("#welcome").hidden) return;
    $("#system-open").click();
  }
});
const page = changeView;
$$("[data-page]").forEach((b) => (b.onclick = () => page(b.dataset.page)));
$$("[data-goto]").forEach((b) => (b.onclick = () => page(b.dataset.goto)));
const colors = {
  utility: "#164BFF",
  entertainment: "#FFE500",
  other: "#F22A30",
};
// A true 16 x 16 binary white foreground, enlarged only by nearest-neighbor sampling.
const rows = [
  0, 0, 0, 0x0ff0, 0x1ff8, 0x1800, 0x1800, 0x1ff0, 0x0ff8, 0x0018, 0x0018, 0x1ff8, 0x0ff0, 0, 0, 0,
];
$$(".pixel-logo").forEach((canvas) => {
  const c = canvas.getContext("2d");
  c.fillStyle = colors[canvas.dataset.category];
  c.fillRect(0, 0, 16, 16);
  c.fillStyle =
    canvas.dataset.category === "entertainment" ? "#000000" : "#FFFFFF";
  rows.forEach((row, y) => {
    for (let x = 0; x < 16; x++)
      if (row & (1 << (15 - x))) c.fillRect(x, y, 1, 1);
  });
});
const sealApp = initSeal({ t, page, getPreferences: () => prefs, setLanguage: (language) => { prefs.language = language; save(); sync(); } });
const welcome = initWelcome({
  showInitially: localStorage.getItem("seal-onboarded") !== "true",
  motionAllowed,
  onStart: (finishWelcome) => {
    const site = $("#site"),
      boot = $("#welcome");
    // Replay always reconstructs the same actual overview hero, as in the source.
    site.dataset.view = "overview";
    $$("section[data-view]").forEach(
      (el) => (el.hidden = el.dataset.view !== "overview"),
    );
    $$(".nav").forEach((el) =>
      el.classList.toggle("active", el.dataset.page === "overview"),
    );
    $("#main").scrollTop = 0;
    const finish = () => {
      finishWelcome();
      delete site.dataset.assembling;
      for (const el of site.children) el.inert = false;
      document.body.classList.remove("boot-visible", "portal-opening");
    };
    if (!motionAllowed()) {
      finish();
      return;
    }
    site.dataset.assembling = "true";
    document.body.classList.add("portal-opening");
    const mark = boot.querySelector(".boot-symbol"),
      destination = site.querySelector(".brand-home .pixel-logo");
    const from = mark.getBoundingClientRect(),
      to = destination.getBoundingClientRect();
    const logo = {
      beginTransfer() {
        mark.style.transformOrigin = "0 0";
      },
      transfer(p) {
        mark.style.transform = `translate(${(to.x - from.x) * p}px,${(to.y - from.y) * p}px) scale(${1 + (to.width / from.width - 1) * p})`;
      },
      finishTransfer() {
        mark.style.transform = "";
      },
    };
    runAssembly({ boot, site, logo, onFinish: finish });
  },
  onFinish: () => {
    localStorage.setItem("seal-onboarded", "true");
    $("#footer-status").textContent = "READY";
    $("#main").focus({ preventScroll: true });
  },
});
$("#replay").onclick = async () => {
  $("#system-close").click();
  await new Promise((r) => setTimeout(r, motionAllowed() ? 450 : 0));
  welcome.show();
};
window.addEventListener("error", (e) => {
  const box = $("#error");
  box.hidden = false;
  box.textContent = e.message;
});
