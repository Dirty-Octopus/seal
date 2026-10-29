export const defaults = Object.freeze({
  treatment: "halftone",
  motion: true,
  sound: true,
  softness: 0.2,
  language: "zh",
  appearance: "system",
});
export function sanitize(value = {}) {
  return {
    treatment: ["classic", "halftone", "mono"].includes(value.treatment)
      ? value.treatment
      : defaults.treatment,
    motion: typeof value.motion === "boolean" ? value.motion : true,
    sound: typeof value.sound === "boolean" ? value.sound : true,
    softness:
      typeof value.softness === "number" && Number.isFinite(value.softness)
        ? Math.min(0.8, Math.max(0, value.softness))
        : 0.2,
    appearance: ["system", "light", "dark"].includes(value.appearance)
      ? value.appearance
      : "system",
    language: ["zh", "en"].includes(value.language) ? value.language : "zh",
  };
}
export function loadPreferences(storage) {
  try {
    return sanitize(JSON.parse(storage.getItem("seal-interface") || "{}") || {});
  } catch {
    return { ...defaults };
  }
}
