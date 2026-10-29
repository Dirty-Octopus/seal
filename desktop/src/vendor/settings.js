/** One clipped surface grows out of the trigger; the original icon travels with it. */
import { EASE, MOTION } from "./motion.js";
export function initSettings({ motionAllowed, onOpen }) {
  const dialog = document.querySelector("#system-dialog");
  const trigger = document.querySelector("#system-open");
  const backdrop = document.querySelector(".system-backdrop");
  const content = dialog.querySelector(".system-content");
  const emblem = dialog.querySelector(".system-emblem");
  const site = document.querySelector("#site");
  const icon = trigger.querySelector("[data-icon]");
  let animations = [],
    serial = 0,
    closing = false;
  let iconOrigin;
  const geometry = (rect) => ({
    left: `${rect.left}px`,
    top: `${rect.top}px`,
    width: `${rect.width}px`,
    height: `${rect.height}px`,
  });
  function destination() {
    const source = trigger.getBoundingClientRect();
    const width = Math.min(408, innerWidth - 28);
    // Leave enough inner room for the reset control so language changes do not
    // move the settings content through an automatic scroll offset.
    const height = Math.min(560, innerHeight - 80);
    return {
      width,
      height,
      left: Math.max(
        14,
        Math.min(innerWidth - width - 14, source.right - width),
      ),
      top: Math.max(48, Math.min(source.top, innerHeight - height - 32)),
    };
  }
  async function morph(opening) {
    if (opening && dialog.open && !closing) return;
    if (!opening && (!dialog.open || closing)) return;
    const ticket = ++serial;
    const from = dialog.open
      ? dialog.getBoundingClientRect()
      : trigger.getBoundingClientRect();
    const iconRect = icon.getBoundingClientRect();
    if (!dialog.open)
      iconOrigin = {
        left: `${iconRect.left - from.left}px`,
        top: `${iconRect.top - from.top}px`,
      };
    const contentFrom = dialog.open
      ? {
          opacity: getComputedStyle(content).opacity,
          transform: getComputedStyle(content).transform,
        }
      : { opacity: 0, transform: "translateY(-12px)" };
    const backdropFrom = dialog.open ? getComputedStyle(backdrop).opacity : 0;
    animations.forEach((animation) => animation.cancel());
    closing = !opening;
    if (opening) {
      if (!dialog.open) dialog.show();
      onOpen();
      site.inert = true;
      trigger.classList.add("expanded");
      trigger.setAttribute("aria-expanded", "true");
      emblem.replaceChildren(icon);
      backdrop.hidden = false;
    }
    dialog.classList.toggle("morph-closing", !opening);
    content.inert = true;
    const to = opening ? destination() : trigger.getBoundingClientRect();
    if (opening) {
      content.style.width = `${to.width - 2}px`;
      content.style.height = `${to.height - 2}px`;
    }
    Object.assign(dialog.style, geometry(to));
    const iconFrom = {
      left: `${iconRect.left - from.left}px`,
      top: `${iconRect.top - from.top}px`,
    };
    const iconTo = opening ? { left: "25px", top: "17px" } : iconOrigin;
    Object.assign(emblem.style, iconTo);
    if (motionAllowed()) {
      const duration = opening ? MOTION.expand : 360;
      animations = [
        dialog.animate([geometry(from), geometry(to)], {
          duration,
          easing: opening ? EASE.glide : EASE.close,
          fill: "both",
        }),
        emblem.animate([iconFrom, iconTo], {
          duration,
          easing: EASE.glide,
          fill: "both",
        }),
        content.animate(
          [
            contentFrom,
            {
              opacity: opening ? 1 : 0,
              transform: opening ? "none" : contentFrom.transform,
            },
          ],
          {
            duration: opening ? MOTION.reveal : MOTION.micro,
            delay: opening ? 140 : 0,
            fill: "both",
            easing: EASE.glide,
          },
        ),
        backdrop.animate(
          [{ opacity: backdropFrom }, { opacity: opening ? 1 : 0 }],
          { duration, fill: "both" },
        ),
      ];
      await Promise.all(
        animations.map((animation) => animation.finished.catch(() => {})),
      );
    }
    if (ticket !== serial) return;
    animations.forEach((animation) => animation.cancel());
    animations = [];
    if (opening) {
      content.inert = false;
      document.querySelector("#system-close").focus({ preventScroll: true });
    } else {
      dialog.close();
      backdrop.hidden = true;
      site.inert = false;
      trigger.prepend(icon);
      trigger.classList.remove("expanded");
      trigger.setAttribute("aria-expanded", "false");
      trigger.focus({ preventScroll: true });
      closing = false;
    }
  }
  trigger.addEventListener("click", () => morph(true));
  document
    .querySelector("#system-close")
    .addEventListener("click", () => morph(false));
  backdrop.addEventListener("click", () => morph(false));
  document.addEventListener("keydown", (event) => {
    if (!dialog.open) return;
    if (event.key === "Escape") {
      event.preventDefault();
      morph(false);
    }
    if (event.key === "Tab") {
      const controls = [...content.querySelectorAll("button,input")].filter(
        (element) => !element.disabled && element.getClientRects().length,
      );
      const index = controls.indexOf(document.activeElement);
      if (
        index < 0 ||
        (event.shiftKey ? index === 0 : index === controls.length - 1)
      ) {
        event.preventDefault();
        controls[event.shiftKey ? controls.length - 1 : 0]?.focus();
      }
    }
  });
  window.addEventListener("resize", () => {
    if (!dialog.open || animations.length || closing) return;
    const to = destination();
    Object.assign(dialog.style, geometry(to));
    content.style.width = `${to.width - 2}px`;
    content.style.height = `${to.height - 2}px`;
  });
}
