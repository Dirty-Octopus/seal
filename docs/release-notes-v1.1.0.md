# Seal v1.1.0

This release adds batch signing management.

## New

- Batch queue for apps, frameworks, plugins, and Mach-O binaries.
- Drop multiple files at once, or add files from the open panel.
- Inspect all queued items before signing.
- Sign the entire queue sequentially with the selected identity and options.
- Stop a running batch after the current item.
- Per-item state, signature status, error message, progress, and activity.
- Retry a single item, reveal it in Finder, open it in the single-file view, or remove it.
- Clear completed items or the whole queue.
- Shared signing options for the batch: deep signing, metadata preservation, Hardened Runtime, timestamp, entitlements, and quarantine removal.

## Install

Download the DMG or ZIP, move `Seal.app` to `/Applications`, then run:

```bash
xattr -dr com.apple.quarantine /Applications/Seal.app
codesign --force --deep --sign - /Applications/Seal.app
open /Applications/Seal.app
```

This release is ad-hoc signed and not notarized by Apple.

## Notes

- Version: 1.1.0 (build 3)
- Universal binary: arm64 + x86_64
- Existing settings from earlier versions are preserved.
