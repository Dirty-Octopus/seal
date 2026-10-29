const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/<>[]{}+-_*";
const running = new Map();

export function clearScramble() {
  for (const [element, frame] of running) {
    cancelAnimationFrame(frame);
    element.classList.remove("ascii-scramble");
    element.removeAttribute("data-ascii");
  }
  running.clear();
}

export function scrambleText(root = document) {
  if (
    document.body.classList.contains("motion-off") ||
    matchMedia("(prefers-reduced-motion: reduce)").matches
  )
    return;
  root
    .querySelectorAll(
      "[data-zh][data-en],h2,h3,#module-path,#workspace-label,.nav b",
    )
    .forEach((element, index) => {
      const text = element.textContent;
      if (
        element.children.length ||
        !text.trim() ||
        !element.getClientRects().length
      )
        return;
      cancelAnimationFrame(running.get(element));
      element.classList.remove("ascii-scramble");
      element.style.setProperty("--ascii-ink", getComputedStyle(element).color);
      element.classList.add("ascii-scramble");
      const start = performance.now() + Math.min(index % 5, 4) * 24;
      let last = -1;
      function paint(now) {
        const phase = Math.max(0, Math.floor((now - start) / 35));
        if (now - start >= 360 || !element.isConnected) {
          element.classList.remove("ascii-scramble");
          element.removeAttribute("data-ascii");
          running.delete(element);
          return;
        }
        if (phase !== last) {
          last = phase;
          const resolved = Math.max(0, (now - start - 60) / 300);
          element.dataset.ascii = [...text]
            .map((char, i) =>
              /\s/.test(char) || i / text.length < resolved
                ? char
                : alphabet[(i * 7 + phase * 3) % alphabet.length],
            )
            .join("");
        }
        running.set(element, requestAnimationFrame(paint));
      }
      paint(performance.now());
    });
}
