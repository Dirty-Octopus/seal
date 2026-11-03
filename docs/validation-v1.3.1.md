# Seal 1.3.1 validation — 2026-11-03

## Defaults

Fresh or reset preferences use screen softness `0` and CRT distortion `false`. Persisted explicit choices remain supported. Tests exercise fresh startup, keyboard adjustment of softness, CRT opt-in, Reset and saved preference parsing. The initial CSS and HTML values also use zero softness.

## Builds

- Apple Silicon: native shared-runtime installer and thin application ZIP, using the unchanged official runtime `electron-45.1.0-arm64-f50b306c4c3a8321`.
- Intel: x86_64 standalone DMG and ZIP, including Electron.
- The root packaging script collects these four artifacts with one combined `SHA256SUMS.txt` in `dist/releases/v1.3.1/`.

## Results

- `npm test --prefix desktop`: 15 tests passed.
- `npm run runtime:test --prefix desktop -- ../dist/shared-arm64`: real native helper, two-app hard-link identity for all 244 framework files, one runtime download, cache/offline reuse, failure recovery, signature checks and complete Seal workflow passed. The running shared app reported `arm64`, version `1.3.1`.
- `SEAL_PACKAGED_APP=/absolute/path/to/dist/standalone-x64/Seal.app SEAL_EXPECT_ARCH=x64 node desktop/tests/app.test.mjs`: complete defaults/settings/signing/attributes/batch workflow passed under Rosetta. The running standalone app reported `x64`, version `1.3.1`.
- App versions, architecture and strict nested code signatures verified on both builds.
- Intel DMG integrity and ZIP compressed-data integrity verified.
- The shared application ZIP omits common Electron frameworks; the native package embeds the exact application URL and pinned SHA-256 for v1.3.1.
- All four distributable assets match the combined checksum file. English/Chinese README links and refreshed screenshots reflect the defaults and platform-specific downloads.

The native installer remains an unsigned developer preview. Application signatures are Ad-hoc, and the packages are not notarized. Tests did not modify real `/Applications` directories, invoke privileged Installer execution or run on physical Intel hardware.
