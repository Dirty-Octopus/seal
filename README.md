<h1 align="center">
  <img src="./docs/icon.png" alt="Seal" width="120" />
  <br>
  Seal
</h1>

<h3 align="center">A local macOS GUI for <code>codesign</code> and <code>xattr</code>.</h3>

<p align="center">
  <a href="./README.md">English</a> ·
  <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/Dirty-Octopus/seal/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Dirty-Octopus/seal?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square">
  <img alt="Universal" src="https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-444444?style=flat-square">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

Seal is a native macOS utility for inspecting, verifying, and re-signing code. It wraps the system `codesign`, `xattr`, `spctl`, and `security` tools in a drag-and-drop interface. It supports apps, frameworks, Mach-O binaries, and audio plugin bundles such as VST3, VST, Audio Unit, and AAX.

No account, telemetry, or file upload is involved.

## Preview

| Dark | Light |
| --- | --- |
| ![Dark preview](./docs/preview-dark.png) | ![Light preview](./docs/preview-light.png) |

## Install

Download the latest universal DMG or ZIP from the [Releases page](https://github.com/Dirty-Octopus/seal/releases/latest).

1. Open the DMG and drag `Seal.app` into `/Applications`, or unzip the archive and move it there.
2. If macOS blocks the app on first launch, run the following commands in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Seal.app
codesign --force --deep --sign - /Applications/Seal.app
open /Applications/Seal.app
```

Because this project is open source and the developer has not paid Apple's $99 developer program fee, run the commands above after installation. Alternatively, use Seal to manage your own signature if you have a certificate.

The release is ad-hoc signed, not notarized by Apple. The commands remove the quarantine flag and apply an ad-hoc signature. This is intended for local use; ad-hoc signatures are not a substitute for Developer ID signing or notarization.

Requires macOS 14 or later. The release is a universal binary for Apple Silicon and Intel Macs.

## Supported targets

| Target | Notes |
| --- | --- |
| Apps and bundles | `.app`, `.framework`, `.xpc`, `.appex`, `.bundle`, `.plugin`, `.kext` |
| Audio plugins | `.vst3`, `.vst`, `.component` (Audio Unit), `.aaxplugin` |
| Binaries | Mach-O executables and dynamic libraries |
| Files and folders | Inspect and remove extended attributes |

For plugin bundles, Seal reads the bundle's `Info.plist`, displays the signature chain, and re-signs nested code when deep signing is enabled.

## Features

- Drag and drop a file, app, framework, or audio plugin into the window.
- Inspect the current code signature: identifier, team ID, format, CDHash, authority chain, flags, timestamp, and entitlements.
- Verify signatures with `codesign --verify --deep --strict`.
- Assess app bundles with `spctl` and show the Gatekeeper result.
- List available code-signing identities from the keychain.
- Re-sign with a certificate, or use an ad-hoc signature when no certificate is available.
- Configure deep signing, metadata preservation, Hardened Runtime, timestamping, entitlements, and quarantine removal.
- View extended attributes, including `com.apple.quarantine`, and remove them individually or recursively.
- Built-in activity log with the exact commands that were executed.
- No telemetry and no upload.

## Usage

1. Drop a target into the window, or click **Open File**.
2. Check the signature status and verification result on the left.
3. Open **Re-sign**, select an identity, adjust the options, and click **Quick Re-sign**.
4. Open **Extended Attributes** to inspect or remove xattr entries.

## FAQ

### macOS says Seal is damaged, cannot be opened, or is from an unidentified developer

Use the commands in the [Install](#install) section. The release is ad-hoc signed, not notarized.

### Do I need a paid Apple Developer account?

No, for local use. Ad-hoc signatures are enough for testing on your own Mac. For distribution, use a Developer ID certificate and notarization.

### Does Seal need administrator privileges?

No. Seal operates with the current user's permissions. If a bundle is read-only, copy it to a writable location before signing. Seal does not invoke `sudo`.

### Can Seal sign Apple system apps?

No. System apps are protected by SIP and their volumes are read-only. Copy the app to a writable directory first.

### Does Seal work with VST3, VST, and Audio Unit plugins?

Yes. `.vst3`, `.vst`, `.component`, and `.aaxplugin` bundles are treated as code bundles. Deep signing is enabled by default for these targets.

### Does Seal send files anywhere?

No. Seal does not upload files or collect telemetry. If the timestamp option is enabled, `codesign` may contact Apple's timestamp service.

## Development

Requirements:

- macOS 14 or later
- Xcode with the SwiftUI macro toolchain (tested with Xcode 27.1)
- Command Line Tools alone is not enough for the current SwiftUI macros

Build the app:

```bash
bash scripts/build.sh
```

Install the local build to `/Applications`:

```bash
bash scripts/install.sh
```

The install script first tries a normal copy. Only if permission is insufficient does it open the macOS administrator authentication dialog through `osascript`. It does not run `sudo` by default.

Build a universal release with DMG, ZIP, and SHA-256 checksums:

```bash
bash scripts/package_release.sh
```

Release artifacts are written to `dist/`.

## Contributing

Issues and pull requests are welcome. Please include the macOS version, the target type, and the relevant `codesign` output when reporting a signing problem.

## Acknowledgement

- Apple's `codesign`, `xattr`, `spctl`, and `security` tools.
- SwiftUI and AppKit.
- The UI is inspired by Material 3 Expressive.
- README layout is inspired by [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev).

Seal is not affiliated with Apple.

## Privacy

Seal does not collect usage data and does not upload files. All inspection and signing operations run locally. The optional timestamp option may contact Apple's timestamp service through `codesign`.

## License

MIT. See [LICENSE](./LICENSE).
