# Seal 1.2.0 — local UI migration

Local test build; no release or remote push was performed.

- Rebuilt the desktop UI on AYMDevKitUI's Electron shell (`ad8f98b`).
- Added four functional workspaces: inspection/signing, batch queue, attributes and activity.
- Adopted the blue 16 × 16 S mark, CRT curve/input mapping, typography, panel transitions, sounds and embedded settings.
- Retained local system-tool operations, signing identities, signing options, entitlements, Gatekeeper reports and exact command logs.
- Added a sandboxed preload with explicit IPC operations; system commands use fixed executables and argument arrays.
- Single and batch signing verify the resulting signature before reporting success.
- Recursive quarantine/attribute removal does not follow links into external files.
- Added once-only import of the previous app's language and window settings.
- Retained the Swift implementation as a separate reference build.

## Local verification — 2026-10-30

- `npm test --prefix desktop`: 11 tests passed, including a real temporary VST3 bundle, signing, strict verification, recursive attribute cleanup, external-link protection, subprocess timeout and path authorization.
- `npm run test:app --prefix desktop`: real Electron UI passed on macOS arm64.
- `SEAL_PACKAGED_APP=/absolute/path/to/dist/Seal.app npm run test:app --prefix desktop`: the packaged app passed the same UI workflow.
- UI coverage: onboarding, physical CRT pointer coordinates, native picker, real-file drop through the sandboxed bridge, inspection, real Ad-hoc signing, quarantine removal, escaped xattr content, individual deletion, a three-file signing queue, settings, Command-comma/Escape, Chinese/English, light/dark and the 960 × 680 minimum window without horizontal overflow.
- `bash scripts/build.sh`: produced the local Apple Silicon `dist/Seal.app`.
- `codesign --verify --deep --strict dist/Seal.app`: passed.

The app is ad-hoc signed and not notarized. Certificate-backed signing/timestamping and a universal Intel/Apple Silicon package were not exercised in this local migration. Font/sound assets are bundled. The Electron app is approximately 255 MiB on disk.
