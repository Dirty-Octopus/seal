import { EASE, MOTION, finishAll } from "./motion.js";
const $ = (s) => document.querySelector(s),
  $$ = (s) => [...document.querySelectorAll(s)];
const labels = { overview: 1, batch: 1, attributes: 1, activity: 1 };
let transition = null,
  heightMotion = null,
  pendingView = null,
  generation = 0,
  options = {};
const motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
export const motionAllowed = () =>
  !document.body.classList.contains("motion-off") && !motionPreference.matches;
function commitView(view) {
  document.querySelector(".shell").dataset.view = view;
  document
    .querySelectorAll("section[data-view]")
    .forEach((el) => (el.hidden = el.dataset.view !== view));
  document.querySelectorAll(".nav").forEach((el) => {
    const active = el.dataset.page === view;
    el.classList.toggle("active", active);
    el.setAttribute("aria-current", active ? "page" : "false");
  });
  document.querySelector("#main").scrollTop = 0;
  document.dispatchEvent(new CustomEvent("modulechange", { detail: view }));
}
function settleTransition() {
  generation += 1;
  if (pendingView && pendingView !== $(".shell").dataset.view)
    commitView(pendingView);
  pendingView = null;
  if (transition) {
    transition.forEach((animation) => animation.cancel());
    transition = null;
  }
  heightMotion?.cancel();
  heightMotion = null;
  $(".module-surface").style.height = "";
  $(".shell").classList.remove("reconfiguring");
  $("#main").inert = false;
  $("#main").setAttribute("aria-busy", "false");
  $$(".nav.pending").forEach((el) => el.classList.remove("pending"));
  document.dispatchEvent(
    new CustomEvent("modulesettled", { detail: $(".shell").dataset.view }),
  );
}
export function changeView(view) {
  if (!(view in labels)) return;
  const shell = $(".shell"),
    workspace = $("#main");
  if (view === pendingView || (!transition && shell.dataset.view === view))
    return;
  pendingView = view;
  $$(".nav").forEach((el) =>
    el.classList.toggle("pending", el.dataset.page === view),
  );
  if (!motionAllowed()) {
    options.engine.sfx("scanner");
    settleTransition();
    return;
  }
  if (transition) return;
  shell.classList.add("reconfiguring");
  workspace.inert = true;
  workspace.setAttribute("aria-busy", "true");
  sweep();
}

async function sweep() {
  options.engine.sfx("scanner");
  const ticket = ++generation;
  const surface = $(".module-surface");
  const panels = () => [
    ...surface.querySelector("section[data-view]:not([hidden])").children,
  ];
  const outgoing = panels();
  transition = outgoing.map((el, i) =>
    el.animate(
      [
        { clipPath: "inset(0 0 0 0)", transform: "translateY(0)", opacity: 1 },
        {
          clipPath: "inset(0 0 100% 0)",
          transform: "translateY(-8px)",
          opacity: 0.4,
        },
      ],
      {
        duration: MOTION.close,
        delay: i * 18,
        easing: EASE.close,
        fill: "both",
      },
    ),
  );
  await finishAll(transition);
  if (ticket !== generation) return;
  const from = surface.offsetHeight;
  if (pendingView) commitView(pendingView);
  pendingView = null;
  const to = surface.offsetHeight;
  // Install every incoming first frame before releasing the outgoing masks.
  const incoming = panels().map((el, i) =>
    el.animate(
      [
        {
          clipPath: "inset(0 100% 0 0)",
          transform: "translateY(9px)",
          opacity: 0.5,
        },
        { clipPath: "inset(0 0 0 0)", transform: "translateY(0)", opacity: 1 },
      ],
      {
        duration: MOTION.reveal,
        delay: 70 + i * MOTION.stagger,
        easing: EASE.glide,
        fill: "both",
      },
    ),
  );
  transition.forEach((a) => a.cancel());
  transition = incoming;
  surface.style.height = `${to}px`;
  heightMotion = surface.animate(
    [{ height: `${from}px` }, { height: `${to}px` }],
    {
      duration: MOTION.expand,
      easing: EASE.machine,
      fill: "both",
    },
  );
  const rail = $(".module-wipe");
  transition.push(
    rail.animate(
      [
        { transform: "scaleX(0)", opacity: 0 },
        { transform: "scaleX(1)", opacity: 1, offset: 0.6 },
        { transform: "scaleX(1)", opacity: 0 },
      ],
      { duration: MOTION.expand, easing: EASE.glide, fill: "both" },
    ),
  );
  await finishAll([...transition, heightMotion]);
  if (ticket !== generation) return;
  transition.forEach((a) => a.cancel());
  transition = null;
  heightMotion.cancel();
  heightMotion = null;
  surface.style.height = "";
  const next = pendingView;
  pendingView = null;
  if (next && next !== $(".shell").dataset.view) changeView(next);
  else settleTransition();
}

export function initPageMotion(engine) {
  options = { engine };
  document.addEventListener("motionchange", () => {
    if (!motionAllowed()) settleTransition();
  });
}
