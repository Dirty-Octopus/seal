# Seal v1.0.0

Initial public release.

## Highlights

- Native macOS GUI for `codesign` and `xattr`.
- Drag and drop apps, frameworks, Mach-O binaries, and audio plugin bundles.
- Support for VST3, VST, Audio Unit (`.component`), and AAX plugin bundles.
- Signature inspection: identifier, team ID, CDHash, authority chain, flags, timestamp, entitlements.
- Signature verification with `codesign --verify --deep --strict`.
- Gatekeeper assessment with `spctl` for app bundles.
- Re-sign with a Keychain code-signing identity or an ad-hoc signature.
- Deep signing, entitlements, Hardened Runtime, timestamp, and quarantine options.
- Extended attribute viewer with individual and recursive removal.
- Activity log with exact executed commands.
- Universal build for Apple Silicon and Intel Macs.

## Install

Download the DMG or ZIP, move `Seal.app` to `/Applications`, then run:

```bash
xattr -dr com.apple.quarantine /Applications/Seal.app
codesign --force --deep --sign - /Applications/Seal.app
open /Applications/Seal.app
```

This release is ad-hoc signed and not notarized by Apple.

## Checksums

See `SHA256SUMS.txt` in the release assets.
