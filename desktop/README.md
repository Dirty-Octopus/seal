# Seal desktop

The active Seal 1.2 frontend uses the Electron application shell from [AYMDevKitUI](https://github.com/Dirty-Octopus/AYMDevKitUI), pinned to `ad8f98bd617cc90d6cc8dd6a53c6373d65475642`. It runs offline and calls macOS tools through a sandboxed preload and an allowlisted main-process service.

```sh
npm ci
npm run build
npm run desktop:dev
npm test
npm run test:app
```

From the repository root, `bash scripts/build.sh` creates and ad-hoc signs `dist/Seal.app` for Apple Silicon. It does not install or publish the app. `bash scripts/package_release.sh` is the separate universal DMG/ZIP packaging path; the packaged app workflow is validated on Apple Silicon, and the release includes arm64/x86_64 binaries.

`SEAL_DEV_URL=http://127.0.0.1:1420 npm run desktop:dev` loads the optional Vite development server. Packaged apps always load bundled assets. `npm run dev` starts Vite. Node 22.12+ is required; the local build uses Node 24.

## Files

- `electron.cjs`: window lifecycle, menus, native dialogs, clipboard, Finder and validated IPC.
- `preload.cjs`: narrow `window.seal` bridge, with no general command execution API.
- `backend.cjs`: target authorization, argument generation, command execution, signature inspection, signing and extended attributes.
- `src/seal.js`, `src/seal.css`: Seal's four workspaces and session state.
- `src/main.js`: AYM shell initialization, preferences, audio, welcome and settings integration.
- `src/vendor/`, `src/appearance*`, `src/language-layout.js`, `src/ambient.js`: adapted AYM interface machinery.
- `tests/backend.test.cjs`: macOS service tests, using disposable files and a locally compiled test plugin.
- `tests/app.test.mjs`: real Electron UI tests, real CRT pointer coordinates and disposable signing targets. Screenshots go to `../dist/qa/`.

## Behavior

The single-file workspace inspects signatures and attributes together. Re-signing and batch signing both verify the result before reporting success. Batch jobs snapshot the identity/options and run sequentially; Stop waits for the current item. Ad-hoc is the default identity. Deep signing, metadata preservation and quarantine removal default to on. Timestamping is available only for certificate identities.

Paths are authorized when selected in the native picker, dropped through Electron's `webUtils`, opened by macOS or supplied through the `--inspect` / repeated `--batch` development arguments. The service rechecks canonical paths for each operation. All subprocesses use fixed system executables and argument arrays, bounded output, timeouts and forced termination if necessary. Attribute recursion operates on symbolic links themselves, preserving external linked targets.

Bulk attribute clearing requires a native confirmation dialog. Individual removals are direct. The list shows top-level attributes; the recursive switch affects deletions. macOS may retain or recreate protected metadata such as `com.apple.provenance`.

Language, appearance, display treatment, sound, motion, CRT, softness, onboarding and window presets are persisted locally. Existing Swift-app language/window settings are imported once. Queues, identities, signing options and the last 100 activity entries are session-only. The application has no updater, account or upload service. Optional certificate timestamping may contact Apple through `codesign`.

## Upstream and licenses

See [AYMDevKitUI-LICENSE](./AYMDevKitUI-LICENSE), [UPSTREAM.md](./UPSTREAM.md) and `licenses/` for the interface and bundled font licenses. The previous SwiftUI implementation remains in the repository's `Sources/` and `Package.swift` as reference; it is not the active desktop runtime.

For a predownloaded official Electron runtime, set `SEAL_ELECTRON_DIST` to a folder containing `electron-v45.1.0-darwin-arm64.zip` and `electron-v45.1.0-darwin-x64.zip` before running the root release script. Verify both against `node_modules/electron/checksums.json`; the override only changes the runtime source and does not publish artifacts.
