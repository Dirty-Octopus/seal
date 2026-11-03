# Seal v1.3.0 — Shared Runtime Preview

Seal now reuses AYMDevKitUI's published Electron runtime instead of shipping a complete Electron framework archive with every application.

This is an **Apple Silicon developer preview for macOS 14+**. The installer is unsigned, application code is Ad-hoc signed, and the preview is not notarized. Privileged macOS Installer execution has not been validated; installation logic was tested using the actual native helper in isolated, unprivileged roots. The [v1.2.0 standalone universal release](https://github.com/Dirty-Octopus/seal/releases/tag/v1.2.0) remains available for Intel Macs and users who prefer an independent bundle.

## Download and install

Download **Seal-Shared-arm64-Preview.pkg** and open it with macOS Installer. Quit all running copies of Seal first. The installed application is `/Applications/Andy Yu/Seal.app`; an older `/Applications/Seal.app` is not removed automatically.

- Native online installer: approximately **56 KiB**.
- Seal application download: approximately **4.1 MiB**.
- First compatible runtime download: approximately **113 MiB**, reused by later compatible applications.
- `SHA256SUMS.txt`: checksums for the installer and thin application archive.

The application ZIP is an immutable installer dependency, **not a standalone application download**. The installer obtains the runtime from AYMDevKitUI's official Release and downloads Seal's archive from this Release. Both archives have pinned SHA-256 values. Target Macs do not need Node.js, Python or developer tools. Installed applications run offline.

## Changes

- Shared runtime: `electron-45.1.0-arm64-f50b306c4c3a8321`, hosted by [AYMDevKitUI](https://github.com/Dirty-Octopus/AYMDevKitUI/releases/tag/runtime-45.1.0-arm64-preview).
- Independent app bundles, executables, helpers, processes and profiles; common framework files share physical storage through hard links.
- Native installer verifies runtime contents and the fully reconstructed application before replacing an installed copy. Failed downloads preserve an existing app.
- Re-signing and attribute operations reject shared hard-linked files and immutable runtime caches, protecting other applications. Copy a target to independent files before modifying it; never re-sign installed shared frameworks in place.
- Existing signature inspection, signing identities/options, entitlements, attributes, activity logging and batch signing remain available.
- Updated English/Chinese README, source mapping and build documentation. Explicit standalone packaging remains available.

## Validation

- 13 automated service/interface tests passed.
- Two applications shared all **244** regular framework files by device/inode identity, with one runtime download and no second runtime download.
- Runtime/offline reuse, bad archive rejection, corrupt-cache rejection, failed-update preservation, strict signatures and uninstall isolation passed.
- Two real Seal processes retained separate profiles, sandboxed renderers, context isolation and independent quit behavior.
- The complete signing, attributes and three-file batch workflow passed against the reconstructed shared application.
- Package contents and SHA-256 checksums verified. No per-app Electron archive is included.

Finder can still show each app's full logical size; the framework files reuse the same physical storage. No real `/Applications` directories were modified by these tests.

## 中文说明

本版改用共享 Electron runtime：应用发布附件约 4.1 MiB，原生安装器约 56 KiB，首次安装所需的约 113 MiB 运行时由官方框架仓库提供，后续兼容应用复用。各应用仍保留独立进程和配置。

请下载并打开 `.pkg`，不要将薄应用 ZIP 当作独立 App。安装或更新前先退出 Seal，安装后从 `/Applications/Andy Yu/Seal.app` 启动；旧的 `/Applications/Seal.app` 不会自动移除。

当前仅支持 Apple Silicon / macOS 14+，属于未签名安装器、Ad-hoc 应用签名、未公证的开发预览。Intel 用户可继续使用 v1.2.0 通用版。共享文件有写入保护，不能原地重签或递归清理其属性。原有签名、扩展属性和批量工作流已完成回归验证。
