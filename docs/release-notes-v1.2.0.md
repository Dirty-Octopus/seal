# Seal v1.2.0

Seal now uses the [AYMDevKitUI](https://github.com/Dirty-Octopus/AYMDevKitUI) desktop interface, with local macOS signing and extended attribute operations.

## Changes

- Four workspaces: Inspect & Sign, Batch Queue, Extended Attributes and Activity.
- AYM CRT curvature with mapped pointer input, pixel-grid identity, bundled fonts, panel transitions and optional interface sounds.
- Chinese/English, system/light/dark appearance, display treatments, motion, CRT softness and window presets in embedded settings.
- Certificate and Ad-hoc signing, shared batch options, entitlements and automatic verification after signing.
- Recursive quarantine cleanup and attribute removal without following links to external files.
- Exact system-command logs, native file selection and multi-file drag and drop.
- Sandboxed renderer with an explicit local IPC bridge. Files are not uploaded.
- One-time import of language/window settings from the previous native app. The Swift implementation remains as a separate reference build.

## Downloads

- **DMG**: open it and drag `Seal.app` into `/Applications`.
- **ZIP**: extract it and move `Seal.app` into `/Applications`.
- **SHA256SUMS.txt**: checksums for both packages.

The universal app includes **arm64 and x86_64** code and requires **macOS 14+**. Node.js and Xcode are not required to run the packaged app.

## First launch

The app is **ad-hoc signed and not notarized by Apple**. If macOS blocks a downloaded copy, confirm its source, then run:

```sh
xattr -dr com.apple.quarantine /Applications/Seal.app
codesign --force --deep --sign - --timestamp=none /Applications/Seal.app
open /Applications/Seal.app
```

Strict signature verification and Gatekeeper acceptance are separate outcomes. Certificate signing with timestamping may contact Apple's timestamp service; other file operations run locally.

## Validation

- 11 automated service/interface tests, including real signing and strict verification on a temporary VST3 bundle.
- Packaged-app UI workflow on Apple Silicon: native picker, real-file drop, CRT pointer mapping, signing, quarantine cleanup, safe xattr rendering/removal, three-file batch signing, settings, language/appearance changes and compact layout.
- Universal architecture and strict application-signature checks.
- DMG/ZIP integrity checks and SHA-256 checksums.

Certificate-backed timestamping and physical Intel hardware have not been tested in this release.

## 中文说明

本版使用 AYMDevKitUI 重构桌面界面，提供「检查与签名」「批量队列」「扩展属性」「活动记录」四个工作区，保留本地签名、证书选择、Entitlements 和批量处理功能。

支持中英文、深浅色、CRT 曲面、面板转场、可关闭的动效与音效。安装包为 Apple Silicon / Intel 通用版，需要 macOS 14+；使用成品无需安装开发工具。首次启动如被 macOS 拦截，确认来源后执行上方安装命令。应用使用 Ad-hoc 签名，未经过 Apple 公证。
