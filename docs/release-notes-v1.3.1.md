# Seal v1.3.1

Screen softness now defaults to **0**, and CRT distortion defaults to **off**. These defaults apply to fresh preferences and Reset settings. Existing saved choices remain unchanged, and both controls can still be enabled manually.

## Downloads

| Platform | Download | Installation |
| --- | --- | --- |
| Apple Silicon | **Seal-Shared-arm64-Preview.pkg** | Native online installer; reuses the pinned AYM Electron runtime |
| Intel | **Seal-1.3.1-macos-intel.dmg** or **Seal-1.3.1-macos-intel.zip** | Standalone x86_64 app with Electron included |

Both require **macOS 14+**. Target Macs do not need developer tools.

### Apple Silicon shared runtime

Quit all running copies of Seal, then open the `.pkg`. It downloads or reuses the official runtime, downloads Seal's small application archive, reconstructs and verifies the complete app, then installs it at `/Applications/Andy Yu/Seal.app`.

The thin `com.andyyu.seal-1.3.1-arm64-<hash>.zip` is a pinned installer dependency, **not a standalone application**. The first compatible installation also downloads approximately 113 MiB of shared runtime; later applications reuse it. Do not re-sign or recursively modify shared frameworks in place.

### Intel standalone

Open the DMG and drag `Seal.app` to `/Applications`, or extract the ZIP and move the app there. This app contains its own Electron runtime and does not require the shared-runtime installer.

If macOS blocks a downloaded Intel standalone copy, confirm its source before applying your own signature or removing quarantine. This advice applies to the independent `/Applications/Seal.app`, not managed shared framework files.

## Validation and status

- Fresh startup, Reset, saved preference handling and manual CRT opt-in are covered by tests.
- Apple Silicon shared-runtime reconstruction, inode sharing, runtime/cache validation and the full signing/attributes/batch workflow are checked.
- Intel standalone launch and the same UI/signing workflow are checked under Rosetta on Apple Silicon; physical Intel hardware has not been tested.
- Both app signatures, archive integrity and the combined SHA-256 manifest are verified.

The shared installer remains an unsigned developer preview, code uses Ad-hoc signatures, and these packages are not notarized. Privileged system Installer execution has not been tested. `SHA256SUMS.txt` covers the installer, thin application ZIP and both Intel packages.

## 中文说明

本版将新配置和重置设置后的屏幕柔化默认值改为 **0**，CRT 畸变默认 **关闭**，保留已有设置，仍可手动开启。

Apple Silicon 请下载共享运行时 `.pkg`；薄应用 ZIP 是安装器依赖，不能单独运行。Intel 请下载同一 Release 中的新版独立 DMG/ZIP，无需共享运行时。两者均需要 macOS 14+，无需开发工具。共享安装位置为 `/Applications/Andy Yu/Seal.app`，Intel 独立版位于 `/Applications/Seal.app`。

中英文 README 已同步更新。共享安装器未签名，应用使用 Ad-hoc 签名且未公证；Intel 工作流通过 Rosetta 验证，未在实体 Intel 机器上测试。
