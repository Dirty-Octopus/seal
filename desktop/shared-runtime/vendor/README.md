# Shared Electron runtime for independent macOS apps

Applications install in `/Applications/Andy Yu/`. The immutable runtime cache lives alongside them in `Runtime/<electron-version>-<architecture>-<content-hash>/`.

Each application keeps its own bundle ID, executable, Helper apps, resources, process tree and profile. Its `Contents/Frameworks` directories project the common runtime using **hard links to regular files**, plus the framework's original internal symlinks. Files share device/inode identity and physical disk blocks. No external framework symlinks, modified Chromium build, shared main process or disabled renderer sandbox is required.

This is physical storage sharing, not an external dynamic-loader ABI. Finder can report the full logical size of each app even though the runtime blocks are shared. Removing either an app or a cache entry does not invalidate another app's hard links. There is no automatic deletion of old runtime versions in this first implementation.

## Build

Build the existing standalone app first. Then, from `desktop/`:

```sh
npm run desktop:build
npm run runtime:build -- --output release/shared-preview
npm run runtime:test -- release/shared-preview
```

The build produces:

- A thin application ZIP; shared `.framework` trees are omitted.
- A versioned runtime ZIP, SHA-256 pin and complete file manifest.
- A native Swift installer helper. Target Macs do not need Python, Node, developer tools or a preinstalled Electron.
- A modern flat **product `.pkg`**, the metapackage role historically associated with `.mpkg`. This native online installer contains the helper and pinned manifests. It fetches or reuses the runtime, downloads the small application ZIP, assembles and verifies the complete app in a private staging directory, then replaces the installed app. A failed download never replaces a working app.

The preview requires macOS 13 or later and is built for Apple Silicon. The builder also accepts a matching single-architecture x86_64 app, but that path has not been runtime-tested here.

To package another app against exactly the same signed runtime:

```sh
python3 shared-runtime/build.py \
  --app '/path/to/Other Tool.app' \
  --output release/other-tool \
  --runtime-from release/shared-preview
```

The builder checks the original framework fingerprint, including Electron fuse settings, and signing identity. A different version, architecture, fuse configuration or signature set gets a separate runtime. It never silently reuses a mismatched engine. Products must have distinct bundle IDs and application names/profile paths.

## Download and updates

Default assets live in this repository's GitHub Releases:

`runtime-<electron-version>-<architecture>-preview/<runtime-ID>.zip`

Override the base URL at build time with `--url-base https://...`. The installer accepts HTTPS only in production, pins the ZIP SHA-256, verifies every extracted regular file and internal symlink, and runs strict nested code-signature verification. Existing runtimes undergo the same file validation before reuse. Downloads are staged under a private temporary directory; checksum failures never publish a partial runtime. A global installation lock serializes cache installation and linking.

The application ZIP has its own pinned SHA-256. Even with an installed runtime, installing or updating an app requires access to its small ZIP. Existing apps run offline.

The runtime folder must be root-owned and not writable by other users. Production install scripts only accept the active startup volume. App metadata is checked before linking, and running applications must be closed before updating. Changed cache contents fail closed; they are not accepted just because the directory exists.

Runtime versions are immutable. **Never modify or re-sign installed shared files in place.** Build/sign a new runtime, then install its new content-addressed directory and replace app projections. App-specific auto-updaters must use this packaging flow; an updater that writes inside existing framework files can affect every hard-linked app. Cross-volume hard linking fails explicitly instead of silently copying a second runtime. Keep products in the managed folder.

## Signing and distribution status

The default `--identity -` build is **ad-hoc signed, unsigned at the installer level, and not notarized**. It is a developer preview, not a Gatekeeper-approved consumer release. Do not disable Gatekeeper to distribute it.

For a distribution build, supply the same Developer ID Application identity for the runtime, helper executable and application, plus a Developer ID Installer identity:

```sh
python3 shared-runtime/build.py \
  --app '/path/to/AYM DevKit.app' \
  --identity 'Developer ID Application: ...' \
  --installer-identity 'Developer ID Installer: ...' \
  --notary-profile 'your-notarytool-keychain-profile' \
  --url-base 'https://your-immutable-release-location' \
  --output release/shared-signed
```

Nested code is signed inside-out before hard-link projections are created. The app bundle is then sealed without re-signing shared frameworks. Production signing enables the hardened runtime and JIT entitlement without disabling library validation. Distribution builds require a notarytool keychain profile. The builder submits the complete app first, requires an Accepted result, and staples it before removing the shared frameworks for transport. It then signs, notarizes and staples the bootstrap package separately. After reconstruction, the native installer checks the full app signature and Gatekeeper assessment. This avoids asking the notary service to accept an incomplete application bundle. Developer ID signing, notarization and Installer execution under root still require validation on a release machine with valid credentials; only the ad-hoc preview path has been exercised here.

## Tests

`test-runtime.py` runs the actual compiled installer helper in marked, unprivileged temporary roots. It serves the generated runtime ZIP over loopback HTTP (allowed only in test mode), prepares two separate app fixtures, downloads thin application archives and assembles shared files through the same native install action used by the package. It verifies:

- first-install download and zero network requests on valid-cache reuse;
- Runtime and application SHA-256 rejection, preservation of existing apps on failed downloads, changed-cache rejection and unsafe test-root rejection;
- inode identity of every shared regular file across the cache and both apps;
- strict nested code signatures of completed apps;
- two simultaneous Electron processes, separate profiles, sandboxed renderers, the actual AYM frontend and independent quit behavior;
- removing one app leaves the runtime and the other app valid.

It does not invoke privileged macOS Installer, write into real `/Applications`, or use the user's real app profile. Generated `test-report.json` and screenshots record evidence. Package structure is additionally inspectable with `pkgutil --expand-full` without installing it.
