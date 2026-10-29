// Reserve structural copy heights; intrinsic button backgrounds fit the active locale.
export function reserveLanguageSpace() {
  for (const element of document.querySelectorAll("[data-zh][data-en]")) {
    if (!element.getClientRects().length) continue;
    const clone = element.cloneNode(false);
    clone.removeAttribute("id");
    clone.removeAttribute("data-ascii");
    clone.classList.remove("ascii-scramble");
    clone.setAttribute("aria-hidden", "true");
    const wrapping = element.matches("p");
    const inline =
      element.matches("button") ||
      (element.matches("span") && element.closest("button,.switches label"));
    if (!wrapping && !inline) continue;
    if (inline && element.tagName === "SPAN")
      element.style.display = "inline-block";
    Object.assign(clone.style, {
      position: "fixed",
      visibility: "hidden",
      pointerEvents: "none",
      top: "-10000px",
      left: "0",
      width: wrapping ? `${element.clientWidth}px` : "max-content",
      height: "auto",
      minWidth: "0",
      minHeight: "0",
      maxHeight: "none",
      whiteSpace: wrapping ? "normal" : "nowrap",
      flex: "none",
    });
    element.after(clone);
    let width = 0,
      activeWidth = 0,
      height = 0;
    for (const [language, text] of [
      ["zh-CN", element.dataset.zh],
      ["en", element.dataset.en],
    ]) {
      clone.lang = language;
      clone.textContent = text;
      const r = clone.getBoundingClientRect();
      width = Math.max(width, r.width);
      if (language === document.documentElement.lang) activeWidth = r.width;
      height = Math.max(height, r.height);
    }
    clone.remove();
    if (wrapping) element.style.minHeight = `${Math.ceil(height)}px`;
    else if (
      element.matches(".actions button[data-zh]") &&
      !element.closest("#system-dialog")
    ) {
      element.dataset.languageSized = "";
      element.style.minWidth = "0";
      element.style.width = `${Math.ceil(activeWidth)}px`;
    } else if (
      !element.closest(".treatments,.appearance-options") &&
      !element.matches(".wide")
    )
      element.style.minWidth = `${Math.ceil(width)}px`;
  }
}
export function initLanguageLayout() {
  document.fonts.ready.then(reserveLanguageSpace);
  let timer;
  window.addEventListener("resize", () => {
    clearTimeout(timer);
    timer = setTimeout(reserveLanguageSpace, 150);
  });
  document.addEventListener("modulechange", reserveLanguageSpace);
}
