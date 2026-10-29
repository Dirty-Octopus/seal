// Welcome-only grid; all coordinates are already corrected by the CRT input layer.
export function initWelcome({ motionAllowed, onFinish, onStart = () => {}, showInitially = true }) {
  const welcome = document.querySelector("#welcome"),
    canvas = document.querySelector("#ascii"),
    ctx = canvas.getContext("2d"),
    site = document.querySelector("#site");
  let running = false,
    frame = 0,
    last = 0,
    trail = [],
    ripples = [];
  const glyphs = "01/+<>[]:=*";
  function size() {
    canvas.width = welcome.clientWidth;
    canvas.height = welcome.clientHeight;
  }
  new ResizeObserver(size).observe(welcome);
  function location(e) {
    const r = welcome.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }
  welcome.addEventListener("pointermove", (e) => {
    if (!motionAllowed()) return;
    const p = location(e),
      now = performance.now();
    const previous = trail.at(-1);
    if (previous && now - previous.t < 120) {
      const d = Math.hypot(p.x - previous.x, p.y - previous.y);
      for (let i = 1; i <= Math.min(40, Math.floor(d / 4)); i++) {
        const a = i / Math.min(40, Math.floor(d / 4));
        trail.push({
          x: previous.x + (p.x - previous.x) * a,
          y: previous.y + (p.y - previous.y) * a,
          t: now,
        });
      }
    } else trail.push({ ...p, t: now });
    trail = trail.slice(-160);
  });
  welcome.addEventListener("pointerdown", (e) =>
    ripples.push({ ...location(e), t: performance.now() }),
  );
  function draw(now) {
    if (!running) return;
    frame = requestAnimationFrame(draw);
    if (now - last < 33) return;
    last = now;
    const w = canvas.width,
      h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    ctx.font = "10px monospace";
    ctx.textBaseline = "top";
    trail = trail.filter((p) => now - p.t < 650);
    ripples = ripples.filter((p) => now - p.t < 1500);
    for (let y = 4; y < h; y += 16)
      for (let x = 4; x < w; x += 14) {
        const n = (x * 17 + y * 31) % glyphs.length;
        const char =
          glyphs[
            (n + (motionAllowed() ? Math.floor(now / 700) : 0)) % glyphs.length
          ];
        let intensity = 0;
        for (const p of trail) {
          const age = (now - p.t) / 650;
          const d = Math.hypot(x - p.x, y - p.y);
          intensity = Math.max(
            intensity,
            Math.max(0, 1 - d / 32) * Math.min(1, (now - p.t) / 65) * (1 - age),
          );
        }
        for (const p of ripples) {
          const age = (now - p.t) / 1000,
            r = age * 210,
            thickness = 14 / (1 + r / 55);
          const d = Math.abs(Math.hypot(x - p.x, y - p.y) - r);
          intensity = Math.max(
            intensity,
            Math.max(0, 1 - d / Math.max(2, thickness)) * (1 - age / 1.5),
          );
        }
        ctx.fillStyle =
          intensity > 0
            ? `rgba(255,229,0,${0.16 + intensity * 0.7})`
            : "rgba(150,150,150,.16)";
        ctx.fillText(char, x, y);
      }
  }
  function show() {
    document.body.classList.add("boot-visible");
    trail = [];
    ripples = [];
    welcome.hidden = false;
    welcome.style.clipPath = "";
    size();
    if (!running) {
      running = true;
      frame = requestAnimationFrame(draw);
    }
    document.querySelector("#start").focus({ preventScroll: true });
  }
  let entering = false;
  document.querySelector("#start").addEventListener("click", () => {
    if (entering) return;
    entering = true;
    onStart(() => {
      welcome.hidden = true;
      running = false;
      cancelAnimationFrame(frame);
      entering = false;
      onFinish();
    });
  });
  // The app is inert behind the welcome, while the welcome itself remains interactive.
  function sync() {
    for (const child of site.children)
      if (child !== welcome)
        child.inert = !welcome.hidden || site.dataset.assembling === "true";
  }
  new MutationObserver(sync).observe(welcome, {
    attributes: true,
    attributeFilter: ["hidden"],
  });
  sync();
  if (showInitially) show();
  else { welcome.hidden = true; sync(); }
  return { show };
}
