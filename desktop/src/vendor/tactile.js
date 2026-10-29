const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
const ease = (t) => t * t * (3 - 2 * t);
export function initScroll(engine, motionAllowed) {
  const root = document.querySelector("#main");
  const ruler = document.querySelector(".scroll-ruler i");
  const step = 56;
  let active = null,
    frame = 0,
    timer = 0,
    touching = false,
    gesture = null;
  const maxScroll = (el) => Math.max(0, el.scrollHeight - el.clientHeight);
  const scroll = (el, y) => el.scrollTo({ top: y, behavior: "instant" });
  const enabled = () =>
    !document.body.classList.contains("boot-visible") &&
    !document.querySelector("#system-dialog").open;
  function rulerPosition() {
    const progress = clamp(root.scrollTop / (maxScroll(root) || 1), 0, 1);
    ruler.style.top = `${progress * (ruler.parentElement.clientHeight - ruler.offsetHeight)}px`;
    ruler.parentElement.style.backgroundPositionY = `${-root.scrollTop / 7}px`;
  }
  function animate(now) {
    frame = 0;
    if (!active) return;
    const { el, from, start } = active;
    const to = clamp(active.to, 0, maxScroll(el));
    const progress = motionAllowed() ? Math.min(1, (now - start) / 140) : 1;
    scroll(el, from + (to - from) * ease(progress));
    rulerPosition();
    if (progress === 1) {
      engine.sfx("lowerclack");
      active = null;
      return;
    }
    frame = requestAnimationFrame(animate);
  }
  function stop() {
    active = null;
    cancelAnimationFrame(frame);
    frame = 0;
    clearTimeout(timer);
    gesture = null;
  }
  function scrollable(target, direction) {
    for (let el = target; el && el !== document.body; el = el.parentElement) {
      if (el === root) break;
      if (
        !/(auto|scroll)/.test(getComputedStyle(el).overflowY) ||
        maxScroll(el) <= 1
      )
        continue;
      if (
        (direction > 0 && el.scrollTop < maxScroll(el) - 1) ||
        (direction < 0 && el.scrollTop > 0)
      )
        return el;
    }
    return root;
  }
  function begin(el) {
    if (active) stop();
    clearTimeout(timer);
    if (gesture?.el !== el)
      gesture = { el, moved: false, tick: Math.floor(el.scrollTop / step) };
  }
  function settle() {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (touching || !gesture?.moved || !enabled()) return;
      const { el } = gesture;
      gesture = null;
      const from = el.scrollTop;
      const to = clamp(Math.round(from / step) * step, 0, maxScroll(el));
      if (Math.abs(to - from) <= 1) {
        scroll(el, to);
        engine.sfx("lowerclack");
        return;
      }
      active = { el, from, to, start: performance.now() };
      frame = requestAnimationFrame(animate);
    }, 160);
  }
  // Keep native wheel velocity and touch inertia; only the resting position snaps.
  document.addEventListener(
    "wheel",
    (event) => {
      if (
        !enabled() ||
        event.ctrlKey ||
        event.metaKey ||
        Math.abs(event.deltaX) > Math.abs(event.deltaY) ||
        event.target.closest("input,textarea,select,[role=slider],.transport")
      )
        return;
      if (!event.deltaY) return;
      const el = scrollable(event.target, Math.sign(event.deltaY));
      if (maxScroll(el) <= 0) return;
      begin(el);
      settle();
    },
    // Run before native scrolling so a previous snap cannot overwrite new input.
    { passive: false },
  );
  document.addEventListener(
    "scroll",
    (event) => {
      rulerPosition();
      if (!gesture || active || !enabled()) return;
      const el = event.target === document ? root : event.target;
      if (el !== gesture.el) begin(el);
      gesture.moved = true;
      const tick = Math.floor(el.scrollTop / step);
      if (tick !== gesture.tick) engine.sfx("lowerclack");
      gesture.tick = tick;
      settle();
    },
    true,
  );
  document.addEventListener("pointerdown", (event) => {
    // A new interaction must also cancel a pending snap when it starts on a control.
    stop();
    touching = false;
    if (
      !enabled() ||
      event.target.closest(
        "[role=slider],input,textarea,select,dialog,.transport",
      )
    )
      return;
    touching = true;
    begin(scrollable(event.target, 1));
  });
  function endTouch() {
    touching = false;
    settle();
  }
  document.addEventListener("pointerup", endTouch);
  document.addEventListener("pointercancel", (event) => {
    // Touch scrolling cancels the pointer while the finger is still on screen.
    if (event.pointerType !== "touch") endTouch();
  });
  document.addEventListener(
    "touchend",
    (event) => {
      if (!event.touches.length) endTouch();
    },
    { passive: true },
  );
  document.addEventListener("touchcancel", endTouch, { passive: true });
  document.addEventListener("keydown", (event) => {
    if (event.target.closest("input,textarea,select,button,[role=slider]"))
      return;
    if (
      ["ArrowDown", "ArrowUp", "PageDown", "PageUp", "Home", "End"].includes(
        event.key,
      )
    ) {
      stop();
      begin(scrollable(event.target, event.key.includes("Up") ? -1 : 1));
    }
  });
  document.addEventListener("modulechange", stop);
  window.addEventListener("resize", rulerPosition);
  new ResizeObserver(rulerPosition).observe(document.body);
  rulerPosition();
}

export function initNoise(motionAllowed) {
  const canvas = document.querySelector("#screen-noise");
  const context = canvas.getContext("2d", { alpha: false });
  // Fine phosphor grain remains fine on large displays, instead of scaling
  // a tiny 240px texture into visible blocks across the portal.
  let noise;
  function resizeNoise() {
    const resolution = Math.min(0.5, 960 / innerWidth, 600 / innerHeight);
    canvas.width = Math.ceil(innerWidth * resolution);
    canvas.height = Math.ceil(innerHeight * resolution);
    noise = context.createImageData(canvas.width, canvas.height);
  }
  resizeNoise();
  window.addEventListener("resize", resizeNoise);
  function draw() {
    if (!document.hidden && motionAllowed()) {
      const pixels = noise.data;
      for (let i = 0; i < pixels.length; i += 4) {
        pixels[i] = Math.random() * 255;
        pixels[i + 1] = Math.random() * 255;
        pixels[i + 2] = Math.random() * 255;
        pixels[i + 3] = 255;
      }
      context.putImageData(noise, 0, 0);
    }
    setTimeout(draw, 100);
  }
  draw();
}
