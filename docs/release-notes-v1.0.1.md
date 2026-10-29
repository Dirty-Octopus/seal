# Seal v1.0.1

This update focuses on first-run setup, localization, and window layout.

## New

- Bilingual first-run language picker: English or Simplified Chinese.
- Full English and Simplified Chinese interface, switchable from Settings.
- Settings panel for interface language and window size presets.
- Window presets: Compact 1040 × 720, Standard 1180 × 820, Large 1380 × 920.
- Responsive workspace: two columns on wide windows, stacked layout on compact windows.
- The window remains freely resizable from the bottom-right corner.

## Install

Download the DMG or ZIP, move `Seal.app` to `/Applications`, then run:

```bash
xattr -dr com.apple.quarantine /Applications/Seal.app
codesign --force --deep --sign - /Applications/Seal.app
open /Applications/Seal.app
```

This release is ad-hoc signed and not notarized by Apple.

## Notes

- Version: 1.0.1 (build 2)
- Universal binary: arm64 + x86_64
- Existing settings from v1.0.0 are preserved.
