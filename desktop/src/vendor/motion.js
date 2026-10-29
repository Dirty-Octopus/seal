// Shared motion language: structure leads, content follows, controls settle quickly.
export const EASE = Object.freeze({
  glide: "cubic-bezier(.16,.82,.2,1)",
  close: "cubic-bezier(.55,.05,.8,.4)",
  machine: "cubic-bezier(.7,0,.2,1)",
});
export const MOTION = Object.freeze({
  micro: 180,
  close: 220,
  reveal: 480,
  stagger: 55,
  expand: 680,
});
export const finishAll = (animations) =>
  Promise.all(animations.map((a) => a.finished.catch(() => {})));
