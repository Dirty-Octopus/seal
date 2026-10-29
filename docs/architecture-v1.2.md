# Seal 1.2 architecture

The active application resides in `desktop/`. AYMDevKitUI provides the local Electron shell and interaction system; Seal adds the macOS service bridge and product workspaces.

```text
Renderer (sandbox, no Node)
  src/main.js     AYM shell, welcome, settings, appearance, sound
  src/seal.js     selection, four workspaces, batch sequencing, session state
        |
        | window.seal: specific operations only
        v
preload.cjs      contextBridge + IPC, native File -> filesystem path
        |
        v
electron.cjs     validates sender/action, native picker, dialogs, menus, clipboard
        |
        v
backend.cjs      canonical target authorization, parsing, mutations, command runner
        |
        v
macOS tools      codesign / xattr / security / spctl / plutil / du
```

The main process authorizes canonical paths from user selections, validates them again at operation time, and serializes file mutations. The renderer snapshots batch identity/options and processes items sequentially; a stop request does not interrupt the active system command. A failed file remains individually retryable. Signature verification and Gatekeeper assessment are distinct outcomes.

Subprocess output is bounded and commands have a timeout followed by SIGTERM/SIGKILL. The runner never uses a shell. The renderer has no raw executable/argument IPC API. The production app loads bundled HTML, scripts, fonts and WAVs with a local content security policy, blocks navigation/new windows, and has no updater/upload endpoint.

The new desktop preferences live in Electron's per-app user data. `seal-interface`, `seal-crt`, `seal-window`, `seal-onboarded` and `seal-migrated` are app-scoped local-storage entries. The first initialization can import the native app's `app.language` and `window.preset`. Queues, activity and signing settings are not persisted. Original Swift sources and localizations are retained for the separate reference build.

Upstream source mapping and license details: `desktop/UPSTREAM.md`.
