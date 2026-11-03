# Seal 1.3 shared-runtime integration — 2026-11-03

Shared-runtime developer preview for the v1.3.0 release. The 1.2.0 standalone universal release remains available separately.

The build now reuses AYMDevKitUI's published `electron-45.1.0-arm64-f50b306c4c3a8321` runtime. Seal's thin application archive does not contain the four shared framework trees, and its output does not include a separately rebuilt Electron runtime ZIP. The native installer downloads a SHA-256-pinned runtime only when absent, reuses its validated immutable files through hard links, downloads Seal's own archive, and verifies a complete staged app before replacement.

Default install locations are `/Applications/Andy Yu/Seal.app` and `/Applications/Andy Yu/Runtime/<runtimeID>/`. The build-time developer cache is `~/Library/Caches/Andy Yu/SharedElectron`. Applications keep separate launchers, helpers, bundle IDs, assets, processes and user profiles. Existing installed apps can run offline. Finder's logical size may still include the full framework size; the shared inodes reuse physical storage.

## Evidence

- Upstream integration commit: `48e355f61177498b20287049716f6e52a1cf847b`.
- Official bootstrap SHA-256: `0929ad0cc609d6015805d088f7c3cb3ff12298e62950c30b6b5693437bc4588d`.
- Official runtime ZIP SHA-256: `c4bcaffc0e6e8d9224d4463a1d1ec8d0bd93b88aa67fc9008b0cab60195a1ba8`.
- Source framework/fuse fingerprint matches the upstream pin. Build tooling rejects a different fingerprint/version/architecture.
- `npm test --prefix desktop`: 13 tests passed, including signing, symlink isolation and new shared-hard-link/cache mutation guards.
- `npm run runtime:test --prefix desktop -- ../dist/shared-arm64`: real native-helper tests passed in marked, unprivileged temporary roots. Two apps share all 244 regular framework files by device/inode; one runtime download, no second runtime download, offline reuse, bad archive rejection, corrupted-cache rejection, preservation of existing apps on failed application download, strict signatures and uninstall isolation passed.
- Two real Seal processes retained independent profiles, sandboxed renderers, context isolation and independent quit behavior.
- The complete existing Seal workflow passed against the reconstructed shared app, including real Ad-hoc signing and a three-file batch.
- Local package is approximately 56 KiB, with an application ZIP approximately 4.1 MiB. The upstream runtime download remains approximately 113 MiB and is shared across compatible products.

`dist/shared-arm64/build.json` and `test-report.json` record the local artifact paths and verification results. `local/Seal.app` is a complete, already linked app for testing. The runtime pin and source mapping are documented in `desktop/shared-runtime/README.md`.

## Behavior changes

Seal refuses signing or attribute writes that would mutate multiply-linked regular files. Recursive writes scan the entire selected target before modifying it. Production and development runtime caches remain immutable even if only one hard link currently exists. Independent top-level app directory attributes are still manageable.

The default root build and package scripts produce the thin shared-runtime artifacts. Explicit standalone app/universal packaging remains available through `scripts/build_standalone.sh` and `scripts/package_standalone.sh`. The existing 1.2.0 release is unaffected.

## Limits

This follows the upstream arm64 developer preview, retains Seal's macOS 14 floor, uses Ad-hoc code signatures and an unsigned installer, and is not notarized. Privileged system Installer execution, physical Intel hardware and Developer ID distribution were not tested. The pinned application archive is distributed with v1.3.0. Unpublished rebuilds need a new immutable application asset before online installation; complete local test projections need no publication. No real `/Applications` directories were modified.
