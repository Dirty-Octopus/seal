# Seal shared Electron integration

This adapts AYMDevKitUI commit `48e355f61177498b20287049716f6e52a1cf847b`. The runtime pin in `runtime-arm64.json` was extracted from the published native bootstrap, whose SHA-256 is `0929ad0cc609d6015805d088f7c3cb3ff12298e62950c30b6b5693437bc4588d`:

https://github.com/Dirty-Octopus/AYMDevKitUI/releases/tag/runtime-45.1.0-arm64-preview

The exact shared runtime is `electron-45.1.0-arm64-f50b306c4c3a8321`, with ZIP SHA-256 `c4bcaffc0e6e8d9224d4463a1d1ec8d0bd93b88aa67fc9008b0cab60195a1ba8`. Seal's framework/fuse fingerprint must match the official pin; a mismatch is rejected rather than silently producing a separate engine.

## Build

From the repository root:

```sh
bash scripts/build.sh
open dist/shared-arm64/local/Seal.app
npm run runtime:test --prefix desktop -- ../dist/shared-arm64
```

The standalone builder is used as a signing/source intermediate. The deliverables omit shared framework trees: `Seal-Shared-arm64-Preview.pkg`, `com.andyyu.seal-1.3.1-arm64-<hash>.zip` and `SHA256SUMS.txt`. No Electron ZIP is emitted with the app. The default app download URL targets `v1.3.1`; the files must be published there before using the online installer. This integration does not publish assets.

`SEAL_SHARED_CACHE` can select a development cache; its default is `~/Library/Caches/Andy Yu/SharedElectron`. The official ZIP is fetched only when absent, verified against the pin, unpacked to a content-addressed directory and validated file-by-file with strict framework signature checks. A valid cache is reused offline. `SEAL_SHARED_OUTPUT` selects a different output directory. Rebuilds replace only previous successful Seal shared-runtime outputs; an unrelated existing directory is rejected. The complete local test app hard-links the developer cache and is not an installed product.

## Installation

The native helper installs apps into `/Applications/Andy Yu/` and runtime versions into its `Runtime/` subfolder. It downloads the pinned runtime on first install, reuses valid cache entries, downloads the app's own small archive and reconstructs/verifies a complete app before replacement. Each application has private executables, helpers, bundle metadata, resources, processes and profiles. Shared framework regular files use hard links; internal framework symlinks remain internal. Both locations must be on the same volume. Removing one application does not invalidate others. Old runtime versions are not automatically removed.

This is the upstream arm64 developer-preview path, not a universal or notarized release. Seal's package retains the macOS 14 minimum. The installer is unsigned and uses ad-hoc code signatures; system Installer execution with root privileges and Developer ID/notarization require separate release-machine validation. The tests use marked, unprivileged temporary roots and never alter actual installed apps.

## Safety in a signing tool

Shared files must never be re-signed or edited in place. Seal's service rejects signing a target that contains multiply-linked regular files. Individual attribute writes reject a multiply-linked file; recursive writes scan the full selected tree before any write. Managed runtime cache paths are immutable even if only one hard link remains. Independent top-level directory attributes remain writable. Copy the target to independent files before modifying it. This protection applies to both single-file and batch operations.

## Source mapping

- `vendor/RuntimeInstaller.swift`, `vendor/entitlements.plist`, `vendor/README.md`: upstream implementation.
- `vendor/build.py`: upstream builder with one integration patch: package minimum OS derives from the source app instead of a fixed macOS 13 value.
- `build_seal.py`: fixed published runtime reuse, cached-download verification, notices, Seal version/architecture checks, atomic artifact replacement, local hard-link test projection and checksum output.
- `test_runtime.py`, `test_launch.mjs`: real native-helper installation, failure recovery and full Seal UI tests in private roots.

The upstream MIT license is retained at `../AYMDevKitUI-LICENSE`.
