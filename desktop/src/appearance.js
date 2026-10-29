export const resolveAppearance = (choice, systemDark) =>
  choice === "system" ? (systemDark ? "dark" : "light") : choice;
export function initAppearance({ getPreference, motionAllowed }) {
  const system = matchMedia("(prefers-color-scheme: dark)");
  let initialized = false,
    timer;
  function apply() {
    const choice = getPreference(),
      resolved = resolveAppearance(choice, system.matches);
    const root = document.documentElement;
    if (
      initialized &&
      root.dataset.appearance !== resolved &&
      motionAllowed()
    ) {
      root.classList.add("appearance-transition");
      clearTimeout(timer);
      timer = setTimeout(
        () => root.classList.remove("appearance-transition"),
        550,
      );
    }
    root.dataset.appearance = resolved;
    document
      .querySelectorAll("[data-appearance-choice]")
      .forEach((b) =>
        b.setAttribute(
          "aria-pressed",
          String(b.dataset.appearanceChoice === choice),
        ),
      );
    document.dispatchEvent(
      new CustomEvent("appearancechange", { detail: resolved }),
    );
    initialized = true;
  }
  system.addEventListener("change", () => {
    if (getPreference() === "system") apply();
  });
  apply();
  return { apply };
}
