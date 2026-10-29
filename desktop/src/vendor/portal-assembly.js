import { EASE } from "./motion.js";

export const ASSEMBLY_DURATION = 2500;
const phase = (t, a, b) => Math.min(1, Math.max(0, (t - a) / (b - a)));
const smooth = (p) => p * p * (3 - 2 * p);

// Actual page panels, the terrain window and the chrome object share one clock
// and one filtered viewport. Nothing is drawn in an unfiltered overlay.
export function runAssembly({
  boot,
  site,
  logo,
  onFinish,
  duration = ASSEMBLY_DURATION,
}) {
  const animations = [];
  let frame = 0,
    finished = false;
  const visual = boot.querySelector(".portal-visual");
  const hero = site.querySelector(".hero");
  const from = visual.getBoundingClientRect();
  const to = hero.getBoundingClientRect();

  function cue(element, frames, start, span, easing = EASE.glide) {
    if (!element) return;
    const animation = element.animate(frames, {
      duration: span,
      delay: start,
      fill: "both",
      easing,
    });
    animation.pause();
    animation.currentTime = 0;
    animations.push(animation);
  }
  function fade(selector, start, span, root = boot) {
    cue(
      root.querySelector(selector),
      [{ opacity: 1 }, { opacity: 0 }],
      start,
      span,
    );
  }
  function open(selector, start, span, axis = "y") {
    cue(
      site.querySelector(selector),
      [
        { clipPath: axis === "y" ? "inset(0 0 100% 0)" : "inset(0 100% 0 0)" },
        { clipPath: "inset(0 0 0 0)" },
      ],
      start,
      span,
      EASE.machine,
    );
  }
  function arrive(element, start, span, x = 0, y = 14) {
    cue(
      element,
      [
        { opacity: 0, transform: `translate(${x}px,${y}px)` },
        { opacity: 1, transform: "translate(0px,0px)" },
      ],
      start,
      span,
    );
  }

  // Selection retracts; the mark stays alive and carries across the same scene.
  cue(
    boot.querySelector(".portal-controls"),
    [
      { clipPath: "inset(0 0 0 0)", opacity: 1, transform: "translateY(0)" },
      {
        clipPath: "inset(0 0 100% 0)",
        opacity: 0,
        transform: "translateY(-12px)",
      },
    ],
    0,
    380,
    EASE.close,
  );
  boot
    .querySelectorAll(".portal-copy > :not(.boot-symbol)")
    .forEach((el, i) => {
      cue(
        el,
        [
          { opacity: 1, transform: "translateY(0)" },
          { opacity: 0, transform: "translateY(-16px)" },
        ],
        70 + i * 35,
        320,
        EASE.close,
      );
    });
  fade(".portal-caption", 80, 310);
  fade(".boot-rule", 40, 300);
  fade(".boot-foot", 30, 240);
  fade(".portal-visual-title", 60, 230);
  fade(".portal-visual-foot", 60, 230);
  fade(".boot-grid", 300, 500);
  cue(
    boot.querySelector(".boot-face"),
    [
      {
        backgroundColor: getComputedStyle(boot.querySelector(".boot-face"))
          .backgroundColor,
      },
      { backgroundColor: "transparent" },
    ],
    200,
    720,
  );

  // FLIP the terrain window into the real hero. Both sample the identical curve;
  // their optical crossfade happens while they occupy exactly the same bounds.
  const dx = to.left - from.left,
    dy = to.top - from.top;
  cue(
    visual,
    [
      { transform: "translate(0px,0px) scale(1,1)" },
      {
        transform: `translate(${dx}px,${dy}px) scale(${to.width / from.width},${to.height / from.height})`,
      },
    ],
    180,
    1080,
    EASE.machine,
  );
  cue(
    visual,
    [
      {
        clipPath:
          "polygon(24px 0,100% 0,100% calc(100% - 24px),calc(100% - 24px) 100%,0 100%,0 24px)",
      },
      { clipPath: "polygon(0px 0,100% 0,100% 100%,100% 100%,0 100%,0 0px)" },
    ],
    180,
    1080,
    EASE.machine,
  );
  cue(
    hero,
    [
      {
        transform: `translate(${-dx}px,${-dy}px) scale(${from.width / to.width},${from.height / to.height})`,
      },
      { transform: "translate(0px,0px) scale(1,1)" },
    ],
    180,
    1080,
    EASE.machine,
  );
  cue(hero, [{ opacity: 0 }, { opacity: 1 }], 330, 300);
  fade(".portal-visual", 720, 560);

  open(".masthead", 430, 730);
  arrive(site.querySelector(".brand-home"), 1000, 490, -18, 0);
  arrive(site.querySelector(".navigation-caption"), 790, 400, 0, -7);
  site
    .querySelectorAll(".nav")
    .forEach((el, i) => arrive(el, 810 + i * 60, 480, -22, 0));
  open(".header-tools", 1110, 400, "x");
  open(".hero-copy", 1070, 650, "x");
  [
    ".hero-side",
    ".hero-coordinate",
    ".scene-corner",
    ".hero-bottom",
    ".signal-assembly",
  ].forEach((selector, i) => {
    arrive(site.querySelector(selector), 1120 + i * 80, 540, 0, 8);
  });
  open(".chassis-bridge", 1180, 540, "x");
  site
    .querySelectorAll(".chassis-rail")
    .forEach((el, i) => arrive(el, 1290 + i * 70, 560, 0, 0));
  open(".module-path", 1280, 490, "x");
  open(".section-bar", 1370, 490, "x");
  open(".board-notice", 1460, 490, "x");
  open(".workspace", 1430, 760);
  arrive(site.querySelector(".profile-identity"), 1680, 540, -22, 0);
  arrive(site.querySelector(".biography-copy"), 1780, 560, 0, 18);
  arrive(site.querySelector("footer"), 2060, 400);
  arrive(site.querySelector(".transport"), 1960, 540, 0, 26);
  arrive(site.querySelector(".outer-label"), 1230, 460, 0, 0);
  arrive(site.querySelector(".bottom-label"), 2040, 440, 0, 0);
  logo?.beginTransfer();

  function render(time) {
    animations.forEach((animation) => {
      animation.currentTime = time;
    });
    logo?.transfer(smooth(phase(time, 210, 1240)));
  }
  function finish() {
    if (finished) return;
    finished = true;
    cancelAnimationFrame(frame);
    render(duration);
    // Commit visibility first; releasing fills must never expose the portal again.
    onFinish();
    logo?.finishTransfer();
    animations.forEach((animation) => animation.cancel());
    window.removeEventListener("resize", finish);
    document.removeEventListener("motionchange", finish);
  }
  render(0);
  // Local visual inspection of the exact production timeline; absent in builds.
  if (import.meta.env?.DEV) {
    const hold = new URLSearchParams(location.search).get("entry-frame");
    if (hold !== null && Number.isFinite(Number(hold))) {
      render(Math.min(duration, Math.max(0, Number(hold))));
      return { finish };
    }
  }
  window.addEventListener("resize", finish);
  document.addEventListener("motionchange", finish);
  const start = performance.now();
  function tick(now) {
    const time = Math.min(duration, now - start);
    render(time);
    if (time >= duration) finish();
    else frame = requestAnimationFrame(tick);
  }
  frame = requestAnimationFrame(tick);
  return { finish };
}
