export function initBackground(motionAllowed) {
  const root = document.documentElement;
  const canvas = document.createElement("canvas");
  const size = 140;
  canvas.width = canvas.height = size;
  const context = canvas.getContext("2d");
  const grain = context.createImageData(size, size);
  let seed = 4729;
  for (let i = 0; i < grain.data.length; i += 4) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const value = seed >>> 29;
    grain.data.set([value, value, value, 255], i);
  }
  context.putImageData(grain, 0, 0);
  context.fillStyle = "#292929";
  for (let y = 3.5; y < size; y += 7) {
    for (let x = 3.5; x < size; x += 7) {
      context.beginPath();
      context.arc(x, y, 0.85, 0, Math.PI * 2);
      context.fill();
    }
  }
  const darkTile = canvas.toDataURL();
  const light = context.getImageData(0, 0, size, size);
  for (let i = 0; i < light.data.length; i += 4) {
    const value = light.data[i] > 20 ? 198 : 238 - light.data[i];
    light.data[i] = light.data[i + 1] = light.data[i + 2] = value;
  }
  context.putImageData(light, 0, 0);
  const lightTile = canvas.toDataURL();
  const tile = darkTile;
  root.style.setProperty("--ambient-grain", `url(${tile})`);
  const background = document.querySelector("#crt-background");
  background.setAttribute("href", tile);
  background.setAttributeNS("http://www.w3.org/1999/xlink", "xlink:href", tile);

  document.addEventListener("appearancechange", (event) => {
    const tile = event.detail === "light" ? lightTile : darkTile;
    root.style.setProperty("--ambient-grain", `url(${tile})`);
    background.setAttribute("href", tile);
    background.setAttributeNS(
      "http://www.w3.org/1999/xlink",
      "xlink:href",
      tile,
    );
  });

  function position() {
    background.setAttribute("x", String(x));
    background.setAttribute("y", String(y));
  }

  let x = 0,
    y = 0,
    targetX = 0,
    targetY = 0,
    frame = 0,
    previous = 0;
  function draw(now) {
    frame = 0;
    const amount =
      1 - Math.exp(-Math.min(64, now - (previous || now - 16)) / 210);
    previous = now;
    x += (targetX - x) * amount;
    y += (targetY - y) * amount;
    root.style.setProperty("--ambient-x", `${x.toFixed(3)}px`);
    root.style.setProperty("--ambient-y", `${y.toFixed(3)}px`);
    position();
    if (Math.hypot(targetX - x, targetY - y) > 0.01)
      frame = requestAnimationFrame(draw);
    else previous = 0;
  }
  function move(event) {
    if (event.pointerType !== "mouse" || !motionAllowed() || document.hidden)
      return;
    targetX = (event.clientX / innerWidth - 0.5) * -36;
    targetY = (event.clientY / innerHeight - 0.5) * -24;
    if (!frame) frame = requestAnimationFrame(draw);
  }
  function reset() {
    targetX = targetY = 0;
    if (!motionAllowed() || document.hidden) {
      cancelAnimationFrame(frame);
      x = y = frame = previous = 0;
      root.style.setProperty("--ambient-x", "0px");
      root.style.setProperty("--ambient-y", "0px");
      position();
    } else if (!frame) frame = requestAnimationFrame(draw);
  }
  window.addEventListener("pointermove", move, { passive: true });
  document.addEventListener("pointerleave", reset);
  document.addEventListener("motionchange", reset);
  document.addEventListener("visibilitychange", reset);
  position();
}
