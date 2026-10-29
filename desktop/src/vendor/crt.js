const SIZE = 192;
const STRENGTH = 0.042;
const maps = new Map();

// The reserved scrollbar gutter survives portal scroll locking. Measure the
// actual filtered surface, so its lens and hit-testing use the same width.
export const crtViewportWidth = () =>
  document.querySelector(".crt-surface")?.clientWidth ||
  document.documentElement.clientWidth;

function displacement(width, height) {
  const key = `${width}:${height}`;
  if (maps.has(key)) return maps.get(key);
  const scale = Math.max(width, height) * 0.1;
  const pixels = new Uint8ClampedArray(SIZE * SIZE * 4);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const nx = ((x + 0.5) / SIZE) * 2 - 1;
      const ny = ((y + 0.5) / SIZE) * 2 - 1;
      const curvature = STRENGTH * (nx * nx + ny * ny);
      const i = (y * SIZE + x) * 4;
      pixels[i] = 255 * (0.5 + (((nx * width) / 2) * curvature) / scale);
      pixels[i + 1] = 255 * (0.5 + (((ny * height) / 2) * curvature) / scale);
      pixels[i + 3] = 255;
    }
  }
  const map = { pixels, scale };
  maps.clear();
  maps.set(key, map);
  return map;
}

// Sample the same quantized map as feDisplacementMap, including texel interpolation.
export function lensSourcePoint(x, y, width, height) {
  const { pixels, scale } = displacement(width, height);
  const u = Math.max(0, Math.min(SIZE - 1, (x / width) * SIZE - 0.5));
  const v = Math.max(0, Math.min(SIZE - 1, (y / height) * SIZE - 0.5));
  const x0 = Math.floor(u),
    y0 = Math.floor(v);
  const x1 = Math.min(SIZE - 1, x0 + 1),
    y1 = Math.min(SIZE - 1, y0 + 1);
  const sample = (channel) => {
    const top =
      pixels[(y0 * SIZE + x0) * 4 + channel] * (1 - u + x0) +
      pixels[(y0 * SIZE + x1) * 4 + channel] * (u - x0);
    const bottom =
      pixels[(y1 * SIZE + x0) * 4 + channel] * (1 - u + x0) +
      pixels[(y1 * SIZE + x1) * 4 + channel] * (u - x0);
    return ((top * (1 - v + y0) + bottom * (v - y0)) / 255 - 0.5) * scale;
  };
  return { x: x + sample(0), y: y + sample(1) };
}

export function lensDisplayPoint(x, y, width, height) {
  let point = { x, y };
  for (let i = 0; i < 8; i++) {
    const source = lensSourcePoint(point.x, point.y, width, height);
    point = { x: point.x + x - source.x, y: point.y + y - source.y };
  }
  return point;
}

export function initCrtLens(t) {
  const root = document.documentElement;
  const filter = document.querySelector("#crt-lens");
  const mapImage = document.querySelector("#crt-map");
  const control = document.querySelector("#crt-toggle");
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = SIZE;
  const context = canvas.getContext("2d");
  let enabled = false,
    hover = null,
    pending = 0;
  const pointers = new Map();
  const active = () => enabled && !document.fullscreenElement;
  // Portal, chrome object and archive share the same optical surface.
  const inputActive = active;
  const defaultEnabled = () =>
    !matchMedia("(max-width: 640px), (hover: none) and (pointer: coarse)")
      .matches;
  const interactive = "button,a,input,textarea,select,summary,[role=button],[role=slider],video";

  function updateMap() {
    pending = 0;
    if (!active()) return;
    const width = crtViewportWidth(),
      height = innerHeight;
    const { pixels, scale } = displacement(width, height);
    context.putImageData(new ImageData(pixels, SIZE, SIZE), 0, 0);
    filter.setAttribute("filterUnits", "userSpaceOnUse");
    filter.setAttribute("primitiveUnits", "userSpaceOnUse");
    filter.setAttribute("width", String(width));
    filter.setAttribute("height", String(height));
    mapImage.setAttribute("x", "0");
    mapImage.setAttribute("y", "0");
    mapImage.setAttribute("width", String(width));
    mapImage.setAttribute("height", String(height));
    const mapUrl = canvas.toDataURL();
    mapImage.setAttribute("href", mapUrl);
    mapImage.setAttributeNS(
      "http://www.w3.org/1999/xlink",
      "xlink:href",
      mapUrl,
    );
    document
      .querySelector("#crt-displacement")
      .setAttribute("scale", String(scale));
  }
  function scheduleMap() {
    if (!pending && active()) pending = requestAnimationFrame(updateMap);
  }
  function sync() {
    control.setAttribute("aria-checked", String(enabled));
    control.textContent = enabled ? t("开", "ON") : t("关", "OFF");
    root.classList.toggle("crt-mode", active());
  }
  function setEnabled(value, persist = true) {
    enabled = value;
    updateMap();
    sync();
    hover?.classList.remove("crt-hover");
    hover = null;
    pointers.clear();
    try {
      if (persist) localStorage.setItem("seal-crt", String(enabled));
    } catch {
      /* Optional preference. */
    }
  }
  control.addEventListener("click", () => setEnabled(!enabled));
  document.addEventListener("settingsreset", () => {
    setEnabled(defaultEnabled(), false);
    try {
      localStorage.removeItem("seal-crt");
    } catch {
      /* Optional preference. */
    }
  });
  document.addEventListener("languagechange", sync);
  document.addEventListener("fullscreenchange", () => {
    updateMap();
    sync();
  });
  window.addEventListener("resize", scheduleMap);
  new ResizeObserver(scheduleMap).observe(document.body);

  function mapped(event) {
    return lensSourcePoint(
      event.clientX,
      event.clientY,
      crtViewportWidth(),
      innerHeight,
    );
  }
  function targetAt(point) {
    return document.elementFromPoint(point.x, point.y) || document.body;
  }
  function initEvent(event, point) {
    return {
      bubbles: true,
      cancelable: true,
      composed: true,
      clientX: point.x,
      clientY: point.y,
      screenX: event.screenX,
      screenY: event.screenY,
      button: event.button,
      buttons: event.buttons,
      detail: event.detail,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
      altKey: event.altKey,
      metaKey: event.metaKey,
      pointerId: event.pointerId,
      pointerType: event.pointerType,
      isPrimary: event.isPrimary,
      pressure: event.pressure,
      width: event.width,
      height: event.height,
    };
  }
  function hoverAt(target, event, point) {
    const next = target.closest(interactive);
    if (next === hover) return;
    hover?.classList.remove("crt-hover");
    hover?.dispatchEvent(
      new PointerEvent("pointerout", {
        ...initEvent(event, point),
        relatedTarget: next,
      }),
    );
    const previous = hover;
    hover = next;
    hover?.classList.add("crt-hover");
    hover?.dispatchEvent(
      new PointerEvent("pointerover", {
        ...initEvent(event, point),
        relatedTarget: previous,
      }),
    );
  }
  function moveRange(range, point) {
    const rect = range.getBoundingClientRect();
    const min = Number(range.min || 0),
      max = Number(range.max || 100);
    const step = Number(range.step) || 1;
    const style = getComputedStyle(range);
    const halfThumb =
      parseFloat(style.getPropertyValue("--range-thumb-width")) / 2;
    const start = rect.left + parseFloat(style.paddingLeft) + halfThumb;
    const end = rect.right - parseFloat(style.paddingRight) - halfThumb;
    const value =
      min +
      Math.max(0, Math.min(1, (point.x - start) / (end - start))) * (max - min);
    range.value = String(min + Math.round((value - min) / step) * step);
    range.dispatchEvent(new Event("input", { bubbles: true }));
  }

  for (const type of [
    "pointerdown",
    "pointermove",
    "pointerup",
    "pointercancel",
  ]) {
    window.addEventListener(
      type,
      (event) => {
        if (!inputActive() || !event.isTrusted) return;
        const point = mapped(event);
        const held = pointers.get(event.pointerId);
        const captured = held?.target.hasPointerCapture?.(event.pointerId);
        const target = captured || held?.range ? held.target : targetAt(point);
        event.stopImmediatePropagation();
        if (type === "pointerdown") {
          const focus = target.closest(interactive);
          const range = target.closest('input[type="range"]');
          pointers.set(event.pointerId, { target: focus || target, range });
          if (focus) {
            event.preventDefault();
            focus.focus({ preventScroll: true });
            if (range) range.setPointerCapture(event.pointerId);
          }
        }
        if (type === "pointermove" && event.pointerType === "mouse")
          hoverAt(target, event, point);
        target.dispatchEvent(new PointerEvent(type, initEvent(event, point)));
        const range = pointers.get(event.pointerId)?.range;
        if (range && type !== "pointercancel") moveRange(range, point);
        if (type === "pointerup" || type === "pointercancel") {
          if (range)
            range.dispatchEvent(new Event("change", { bubbles: true }));
          pointers.delete(event.pointerId);
        }
      },
      { capture: true, passive: false },
    );
  }
  for (const type of ["pointerover", "pointerout", "mousedown", "mouseup"]) {
    window.addEventListener(
      type,
      (event) => {
        if (inputActive() && event.isTrusted) event.stopImmediatePropagation();
      },
      true,
    );
  }
  window.addEventListener(
    "click",
    (event) => {
      // Keyboard activation has no visual coordinates and already targets its focused control.
      if (!inputActive() || !event.isTrusted || event.detail === 0) return;
      const point = mapped(event);
      const target = targetAt(point);
      event.preventDefault();
      event.stopImmediatePropagation();
      target.dispatchEvent(new MouseEvent("click", initEvent(event, point)));
    },
    true,
  );
  window.addEventListener(
    "wheel",
    (event) => {
      if (!inputActive() || !event.isTrusted) return;
      const point = mapped(event);
      let target = targetAt(point);
      while (target && target !== document.body) {
        const style = getComputedStyle(target);
        if (
          /(auto|scroll)/.test(style.overflowY) &&
          target.scrollHeight > target.clientHeight
        ) {
          event.preventDefault();
          const unit =
            event.deltaMode === 1
              ? 16
              : event.deltaMode === 2
                ? target.clientHeight
                : 1;
          target.scrollBy({
            top: event.deltaY * unit,
            left: event.deltaX * unit,
            behavior: "instant",
          });
          return;
        }
        target = target.parentElement;
      }
    },
    { capture: true, passive: false },
  );
  try {
    const saved = localStorage.getItem("seal-crt");
    setEnabled(saved === null ? defaultEnabled() : saved !== "false", false);
  } catch {
    setEnabled(defaultEnabled(), false);
  }
}
