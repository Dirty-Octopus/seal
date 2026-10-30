<h1 align="center"><img src="./docs/icon.png" alt="Seal" width="100" /><br>Seal</h1>
<p align="center">Local macOS code signing and extended attribute management.</p>
<p align="center"><a href="./README.md">English</a> · <a href="./README.zh-CN.md">简体中文</a></p>
<p align="center"><a href="https://repology.org/projects/?search=seal"><img src="https://img.shields.io/badge/Repology-Packaging%20status-blue" alt="Repology package status" /></a></p>

Seal inspects, verifies and re-signs apps, frameworks, Mach-O binaries and audio plugins. Version 1.2 uses the [AYMDevKitUI](https://github.com/Dirty-Octopus/AYMDevKitUI) Electron application shell with a local macOS process service. Files stay on your Mac; no account or upload is involved.

## Workspaces

- **Inspect & Sign**: drag in an app, plugin or binary, read its signature/entitlements, choose a keychain identity or Ad-hoc, and re-sign with automatic verification.
- **Batch Queue**: inspect and sign multiple targets sequentially, stop after the current item, retry, reveal, open individual items and clear completed entries.
- **Extended Attributes**: inspect quarantine, download origins and other metadata; remove individual entries or clear attributes, optionally recursively.
- **Activity**: copy the last 100 session entries, including the exact commands executed.

Supported bundles include `.app`, `.framework`, `.xpc`, `.appex`, `.bundle`, `.plugin`, `.kext`, `.vst3`, `.vst`, `.component` and `.aaxplugin`. Ordinary files and folders also support attribute operations. Gatekeeper assessment is separate from signature verification and is performed for signed app bundles.

## Interface

The AYM shell provides CRT curvature with mapped pointer input, a 16 × 16 blue utility mark, bundled Barlow Condensed / IBM Plex Mono, panel transitions and interface sounds. Settings include Chinese/English, system/light/dark appearance, display treatment, motion, sound, CRT, softness and window presets. Welcome appears on first launch and can be replayed from Settings.

![Seal interface](./docs/preview-light.png)

## Download and install

Download the universal **DMG** or **ZIP** from [Seal v1.2.0](https://github.com/Dirty-Octopus/seal/releases/tag/v1.2.0). The package includes Apple Silicon (arm64) and Intel (x86_64) code and requires macOS 14 or later. Node.js and Xcode are not required to use the packaged app.

1. Open the DMG and drag `Seal.app` into `/Applications`, or unzip the ZIP and move the app there.
2. The app is ad-hoc signed and not notarized. If macOS blocks the downloaded copy, confirm its source, then run:

```sh
xattr -dr com.apple.quarantine /Applications/Seal.app
codesign --force --deep --sign - --timestamp=none /Applications/Seal.app
open /Applications/Seal.app
```

`SHA256SUMS.txt` is included with the release for checking the DMG and ZIP. Gatekeeper may reject an ad-hoc signature even when strict signature verification passes.

## Local build and testing

Building from source requires macOS 14+ and Node 22.12+. The app and signing workflow are tested on Apple Silicon; the universal package includes both architectures.

```sh
bash scripts/build.sh
open dist/Seal.app
```

The build creates an ad-hoc signed app at `dist/Seal.app`. It does not overwrite `/Applications/Seal.app` or publish anything. The optional `bash scripts/install.sh` installs it separately.

```sh
npm test --prefix desktop
npm run test:app --prefix desktop
```

The first command covers the local services and interface primitives. The second launches real Electron, uses temporary targets for signing and attribute operations, and captures screenshots in `dist/qa/`. Command Line Tools are required to compile the disposable test fixture.

`bash scripts/package_release.sh` builds the universal app, verifies its signature, and generates DMG/ZIP packages with SHA-256 checksums. It does not publish them. The release is not notarized. The previous Swift source remains available as reference; `scripts/build_native.sh` builds it separately to `dist/Seal-native.app`. See [desktop/README.md](./desktop/README.md) for architecture and development details.

## Signing and permissions

Seal uses `codesign`, `xattr`, `security` and `spctl` with the current user's permissions. It does not invoke `sudo`. Copy read-only targets to a writable location before modifying them.

Ad-hoc is the default identity. Deep signing, metadata preservation and quarantine removal are enabled by default. Certificate signing can optionally use Apple's timestamp service. Ad-hoc signing supports local use; distribution signing and notarization are separate processes.

The local app is not notarized. If macOS blocks a downloaded copy, verify its source before removing quarantine or applying your own signature. App signature verification and Gatekeeper acceptance are shown separately.

Language, appearance and window settings persist locally. Queues, signing options and logs are session-only. Recursive attribute deletion acts on symbolic links themselves, leaving external linked targets untouched; macOS may retain or recreate protected attributes such as `com.apple.provenance`.

## License and credits

MIT, see [LICENSE](./LICENSE). The UI is based on AYMDevKitUI at commit `ad8f98b`; its license, source mapping and font licenses are retained in [desktop/UPSTREAM.md](./desktop/UPSTREAM.md). Seal is not affiliated with Apple.
