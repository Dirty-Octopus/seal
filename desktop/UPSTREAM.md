# AYMDevKitUI provenance

- Source: https://github.com/Dirty-Octopus/AYMDevKitUI
- Commit: `ad8f98bd617cc90d6cc8dd6a53c6373d65475642`
- Imported from the committed `desktop/` tree, independently of uncommitted local SwiftUI work.
- License: MIT, reproduced in `AYMDevKitUI-LICENSE`.

Seal uses the actual Electron shell, typography, pixel-grid identity, CRT displacement/inverse input mapping, generated texture, phosphor treatment, sound assets, queued panel transitions, language layout measurement, ASCII language transition, welcome construction, appearance interpolation and settings choreography.

Adaptations:

- Replaced the component gallery with functional Seal workspaces.
- Added an isolated preload, native integration and system-tool service.
- Replaced the gallery mark with Seal's S on the same 16 × 16 grid and utility blue `#164BFF`.
- Namespaced preferences to `seal-interface` and `seal-crt`.
- Changed page IDs in `src/vendor/interface.js`.
- Added `summary` and button roles to CRT hit-testing in `src/vendor/crt.js`.
- Added optional first-run-only welcome display in `src/ambient.js`.
- Added window presets and first-run language/window migration from the native app.
- Retained the kit's no-motion behavior and UI sound controls.

`src/vendor/reference.css`, `background.js`, `tactile.js`, `motion.js`, `portal-assembly.js`, `settings.js`, and `text-transition.js` retain the upstream implementation. Seal's own CSS is layered after the upstream styles. There is no runtime dependency on an adjacent AYMDevKitUI checkout or on GitHub.
