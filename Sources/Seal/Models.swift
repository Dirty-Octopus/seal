import Foundation
import AppKit

// MARK: - Target

enum TargetKind: String {
    case appBundle
    case audioPlugin
    case codeBundle
    case executable
    case file
    case folder

    var label: String {
        switch self {
        case .appBundle: return "App Bundle"
        case .audioPlugin: return L10n.t("音频插件")
        case .codeBundle: return "Code Bundle"
        case .executable: return L10n.t("Mach-O 二进制")
        case .file: return L10n.t("文件")
        case .folder: return L10n.t("文件夹")
        }
    }

    var symbol: String {
        switch self {
        case .appBundle: return "app.fill"
        case .audioPlugin: return "waveform"
        case .codeBundle: return "shippingbox.fill"
        case .executable: return "terminal.fill"
        case .file: return "doc.fill"
        case .folder: return "folder.fill"
        }
    }
}

struct TargetInfo: Equatable {
    let url: URL
    let isDirectory: Bool
    let kind: TargetKind
    var byteSize: Int64
    let modified: Date?
    let bundleID: String?
    let executableName: String

    var isCodeBundle: Bool {
        kind == .appBundle || kind == .audioPlugin || kind == .codeBundle
    }

    var canCodesign: Bool {
        !isDirectory || isCodeBundle
    }

    var displayName: String {
        if kind == .appBundle {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }

    var isSizePending: Bool { byteSize < 0 }

    var sizeText: String {
        if isSizePending { return L10n.t("计算中…") }
        return L10n.byteString(byteSize)
    }

    var parentPath: String {
        url.deletingLastPathComponent().path
    }

    var pluginFamily: String? {
        switch url.pathExtension.lowercased() {
        case "vst3": return "VST3"
        case "vst": return "VST"
        case "component": return "Audio Unit"
        case "aaxplugin": return "AAX"
        default: return nil
        }
    }

    var kindDescription: String {
        if kind == .audioPlugin, let pluginFamily {
            return "\(kind.label) · \(pluginFamily)"
        }
        return kind.label
    }

    var isWritable: Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    var subtitle: String {
        if (kind == .appBundle || kind == .audioPlugin), !executableName.isEmpty {
            return "\(kindDescription) · \(executableName)"
        }
        return kindDescription
    }

    static func make(url: URL, calculateDirectorySize: Bool = true) throws -> TargetInfo {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw SealError.fileNotFound(url.path)
        }

        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .totalFileSizeKey, .contentModificationDateKey, .isDirectoryKey
        ])
        let directory = isDir.boolValue
        let ext = url.pathExtension.lowercased()
        let kind: TargetKind

        if directory {
            switch ext {
            case "app":
                kind = .appBundle
            case "vst3", "vst", "component", "aaxplugin":
                kind = .audioPlugin
            case "framework", "xpc", "bundle", "plugin", "kext", "systemextension", "appex", "qlgenerator", "mdimporter":
                kind = .codeBundle
            default:
                kind = .folder
            }
        } else if isMachO(url) {
            kind = .executable
        } else {
            kind = .file
        }

        let bundle = (kind == .appBundle || kind == .audioPlugin) ? Bundle(url: url) : nil
        let executable = bundle?.executableURL?.lastPathComponent
        let size: Int64
        if directory {
            size = calculateDirectorySize ? directorySize(of: url) : -1
        } else {
            size = Int64(values?.fileSize ?? 0)
        }

        return TargetInfo(
            url: url.standardizedFileURL,
            isDirectory: directory,
            kind: kind,
            byteSize: size,
            modified: values?.contentModificationDate,
            bundleID: bundle?.bundleIdentifier,
            executableName: executable ?? (directory ? "" : url.lastPathComponent)
        )
    }

    static func directorySize(of url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            guard let values = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            let logical = values.fileSize ?? 0
            total += Int64(allocated > 0 ? allocated : logical)
        }
        return total
    }

    private static func isMachO(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "class" { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return [
            0xFEEDFACE, // 32-bit
            0xFEEDFACF, // 64-bit
            0xCAFEBABE, // universal
            0xCAFEBABF, // universal 64
            0xBEBAFECA  // universal, little endian
        ].contains(magic)
    }
}

// MARK: - Signature

enum SignatureStatus: String {
    case signed
    case adHoc
    case unsigned
    case invalid
    case unsupported

    var title: String {
        switch self {
        case .signed: return L10n.t("签名有效")
        case .adHoc: return L10n.t("Ad-hoc 签名")
        case .unsigned: return L10n.t("未签名")
        case .invalid: return L10n.t("签名无效")
        case .unsupported: return L10n.t("无法直接签名")
        }
    }

    var shortTitle: String {
        switch self {
        case .signed: return L10n.t("已签名")
        case .adHoc: return "Ad-hoc"
        case .unsigned: return L10n.t("未签名")
        case .invalid: return L10n.t("无效")
        case .unsupported: return L10n.t("不适用")
        }
    }

    var detail: String {
        switch self {
        case .signed: return L10n.t("代码签名校验通过，签名链完整。")
        case .adHoc: return L10n.t("本机临时签名有效，但没有可识别的开发者证书。")
        case .unsigned: return L10n.t("这个对象还没有代码签名。")
        case .invalid: return L10n.t("签名存在，但没有通过 codesign 校验。")
        case .unsupported: return L10n.t("普通文件夹不能直接签名；请选择 .app、VST/VST3/AU 插件或二进制文件。")
        }
    }

    var symbol: String {
        switch self {
        case .signed: return "checkmark.seal.fill"
        case .adHoc: return "scribble.variable"
        case .unsigned: return "seal"
        case .invalid: return "exclamationmark.triangle.fill"
        case .unsupported: return "questionmark.folder.fill"
        }
    }

    var isSigned: Bool {
        self == .signed || self == .adHoc
    }
}

enum GatekeeperStatus: Equatable {
    case accepted
    case rejected(String)
    case notAssessed(String)

    var title: String {
        switch self {
        case .accepted: return L10n.t("Gatekeeper 已接受")
        case .rejected: return L10n.t("Gatekeeper 未通过")
        case .notAssessed: return L10n.t("Gatekeeper 未评估")
        }
    }

    var detail: String {
        switch self {
        case .accepted: return L10n.t("spctl 评估通过。")
        case .rejected(let reason): return reason
        case .notAssessed(let reason): return reason
        }
    }

    var symbol: String {
        switch self {
        case .accepted: return "checkmark.shield.fill"
        case .rejected: return "xmark.shield.fill"
        case .notAssessed: return "shield.lefthalf.filled"
        }
    }
}

struct SignatureReport {
    var status: SignatureStatus = .unsigned
    var identifier: String?
    var format: String?
    var authorities: [String] = []
    var teamID: String?
    var cdhash: String?
    var flags: [String] = []
    var timestamp: String?
    var signatureSize: String?
    var entitlements: String?
    var verificationPassed: Bool = false
    var verificationOutput: String = ""
    var gatekeeper: GatekeeperStatus = .notAssessed(L10n.t("仅对 App Bundle 评估"))
    var rawDisplay: String = ""

    var authorityLine: String {
        authorities.first ?? (status == .adHoc ? L10n.t("Ad-hoc（无证书链）") : "—")
    }

    var verificationSymbol: String {
        verificationPassed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var verificationTitle: String {
        if status == .unsigned { return L10n.t("未签名，无法验证") }
        if status == .unsupported { return L10n.t("不适用") }
        return verificationPassed ? L10n.t("codesign 校验通过") : L10n.t("codesign 校验失败")
    }
}

// MARK: - xattr

struct XattrItem: Identifiable, Equatable {
    let name: String
    let data: Data
    let summary: String
    let details: [String]

    var id: String { name }

    var byteCountText: String {
        L10n.byteString(Int64(data.count))
    }

    var isQuarantine: Bool {
        name == "com.apple.quarantine"
    }

    var isWhereFrom: Bool {
        name == "com.apple.metadata:kMDItemWhereFroms"
    }

    var isFinderInfo: Bool {
        name == "com.apple.FinderInfo"
    }

    var isResourceFork: Bool {
        name == "com.apple.ResourceFork"
    }

    var symbol: String {
        if isQuarantine { return "clock.badge.exclamationmark" }
        if isWhereFrom { return "link" }
        if isFinderInfo { return "finder" }
        if isResourceFork { return "doc.zipper" }
        if name == "com.apple.provenance" { return "checkmark.shield" }
        return "tag"
    }

    var copyText: String {
        var output = "\(name): \(summary)\n"
        if !details.isEmpty {
            output += details.joined(separator: "\n") + "\n"
        }
        let hex = data.prefix(4096).map { String(format: "%02x", $0) }.joined()
        output += "hex: \(hex)\(data.count > 4096 ? "…" : "")"
        return output
    }
}

enum XattrDecoder {
    static func make(name: String, data: Data) -> XattrItem {
        switch name {
        case "com.apple.quarantine":
            return quarantineItem(name: name, data: data)
        case "com.apple.metadata:kMDItemWhereFroms":
            return whereFromItem(name: name, data: data)
        case "com.apple.FinderInfo":
            return XattrItem(name: name, data: data, summary: L10n.t("Finder 元数据 · %d 字节", data.count), details: [
                L10n.t("这个属性常用于保存 Finder 标签、窗口位置等元数据。"),
                L10n.t("十六进制：%@", data.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " "))
            ])
        case "com.apple.ResourceFork":
            return XattrItem(name: name, data: data, summary: L10n.t("资源分支 · %@", L10n.byteString(Int64(data.count))), details: [
                L10n.t("资源分支可能包含旧的 Classic 资源或自定义元数据。")
            ])
        case "com.apple.provenance":
            let text = String(data: data, encoding: .utf8) ?? data.prefix(80).map { String(format: "%02x", $0) }.joined()
            return XattrItem(name: name, data: data, summary: L10n.t("来源标记 · %@", text), details: [
                L10n.t("provenance：%@", text)
            ])
        default:
            let utf8 = String(data: data, encoding: .utf8)
            let readable = utf8?.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 32 || scalar == "\n" || scalar == "\t" || scalar == "\r"
            } ?? false
            let summary: String
            if let utf8, !utf8.isEmpty, readable, utf8.count <= 180 {
                summary = utf8.replacingOccurrences(of: "\n", with: " ")
            } else if data.isEmpty {
                summary = L10n.t("空值")
            } else {
                summary = data.prefix(18).map { String(format: "%02X", $0) }.joined(separator: " ") + (data.count > 18 ? "…" : "")
            }
            let hex = data.prefix(512).map { String(format: "%02X", $0) }.joined(separator: " ")
            return XattrItem(name: name, data: data, summary: summary, details: [
                L10n.t("大小：%@", L10n.byteString(Int64(data.count))),
                L10n.t("十六进制预览：%@", hex + (data.count > 512 ? " …" : ""))
            ])
        }
    }

    private static func quarantineItem(name: String, data: Data) -> XattrItem {
        guard let raw = String(data: data, encoding: .utf8) else {
            return XattrItem(name: name, data: data, summary: L10n.t("隔离属性 · 无法解析"), details: [])
        }
        let parts = raw.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var lines = [L10n.t("原始值：%@", raw)]
        var summary = L10n.t("隔离属性")

        if parts.count >= 4 {
            let flags = UInt64(parts[0], radix: 16) ?? 0
            let timestamp = UInt64(parts[1], radix: 16) ?? 0
            let agent = parts[2]
            let origin = parts[3]
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            summary = "\(agent) · \(formatter.string(from: date))"
            lines = [
                L10n.t("下载代理：%@", agent),
                L10n.t("下载时间：%@", formatter.string(from: date)),
                L10n.t("来源：%@", origin.isEmpty ? "—" : origin),
                L10n.t("标志：0x%@", String(flags, radix: 16) + quarantineFlagDescription(flags))
            ]
        }

        return XattrItem(name: name, data: data, summary: summary, details: lines)
    }

    private static func quarantineFlagDescription(_ flags: UInt64) -> String {
        var parts: [String] = []
        if flags & 0x1 != 0 { parts.append(L10n.t("已下载")) }
        if flags & 0x2 != 0 { parts.append(L10n.t("沙盒")) }
        if flags & 0x4 != 0 { parts.append(L10n.t("硬隔离")) }
        if flags & 0x40 != 0 { parts.append(L10n.t("用户已批准")) }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " / ")
    }

    private static func whereFromItem(name: String, data: Data) -> XattrItem {
        var urls: [String] = []
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
            urls = plist
        } else if let text = String(data: data, encoding: .utf8) {
            urls = [text]
        }
        let summary = urls.first ?? L10n.t("来源记录")
        return XattrItem(
            name: name,
            data: data,
            summary: summary,
            details: urls.isEmpty ? [L10n.t("无法解析来源 plist。")] : urls.map { L10n.t("来源：%@", $0) }
        )
    }
}

// MARK: - Signing

struct SigningIdentity: Identifiable, Hashable {
    let id: String
    let name: String
    let isAdHoc: Bool

    static let adHoc = SigningIdentity(id: "-", name: "Ad-hoc", isAdHoc: true)

    var displayName: String {
        isAdHoc ? L10n.t("Ad-hoc（本机临时签名）") : name
    }
}

struct SignOptions {
    var force: Bool = true
    var deep: Bool = false
    var preserveMetadata: Bool = true
    var hardenedRuntime: Bool = false
    var timestamp: Bool = false
    var removeQuarantine: Bool = true
    var entitlementsPath: URL?
}

// MARK: - Batch

enum BatchState: String {
    case pending
    case inspecting
    case ready
    case signing
    case signed
    case failed
    case skipped

    var title: String {
        switch self {
        case .pending: return L10n.t("待检查")
        case .inspecting: return L10n.t("检查中")
        case .ready: return L10n.t("待签名")
        case .signing: return L10n.t("签名中")
        case .signed: return L10n.t("已完成")
        case .failed: return L10n.t("失败")
        case .skipped: return L10n.t("已跳过")
        }
    }

    var symbol: String {
        switch self {
        case .pending: return "clock"
        case .inspecting: return "magnifyingglass"
        case .ready: return "checkmark.circle"
        case .signing: return "signature"
        case .signed: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }

    var isCompleted: Bool {
        self == .signed || self == .failed || self == .skipped
    }
}

struct BatchItem: Identifiable {
    let id = UUID()
    var target: TargetInfo
    var report: SignatureReport?
    var state: BatchState = .pending
    var message: String = ""
    var lastUpdated: Date?
}

// MARK: - UI / activity models

enum InspectorTab: String, CaseIterable, Identifiable {
    case resign
    case xattrs
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resign: return L10n.t("重新签名")
        case .xattrs: return L10n.t("扩展属性")
        case .activity: return L10n.t("活动")
        }
    }

    var symbol: String {
        switch self {
        case .resign: return "signature"
        case .xattrs: return "tag.fill"
        case .activity: return "list.bullet.rectangle"
        }
    }
}

enum LogLevel {
    case info
    case success
    case warning
    case error

    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let level: LogLevel
    let message: String
    let command: String?
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

enum ToastStyle {
    case success
    case info
    case error

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "sparkles"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Errors

enum SealError: LocalizedError {
    case fileNotFound(String)
    case commandFailed(String)
    case xattr(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return L10n.t("找不到文件：%@", path)
        case .commandFailed(let message): return message
        case .xattr(let message): return message
        }
    }
}
