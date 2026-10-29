import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var target: TargetInfo?
    @Published var signature: SignatureReport?
    @Published var xattrs: [XattrItem] = []
    @Published var identities: [SigningIdentity] = [.adHoc]
    @Published var selectedIdentityID: String = "-"
    @Published var options = SignOptions()
    @Published var activeTab: InspectorTab = .resign
    @Published var isDropTargeted = false
    @Published var isLoading = false
    @Published var isSigning = false
    @Published var isVerifying = false
    @Published var isWorkingXattrs = false
    @Published var isLoadingIdentities = false
    @Published var xattrRecursive = false
    @Published var errorMessage: String?
    @Published var identityNote: String?
    @Published var toast: ToastMessage?
    @Published var activity: [LogEntry] = []
    @Published var lastUpdated: Date?
    @Published var clearAllConfirmation = false

    private var inspectionID = UUID()
    private var hasLoadedIdentities = false

    var selectedIdentity: SigningIdentity {
        identities.first(where: { $0.id == selectedIdentityID }) ?? .adHoc
    }

    var hasExistingSignature: Bool {
        signature?.status.isSigned == true
    }

    var signatureStateText: String {
        guard let signature else { return "签名尚未读取" }
        switch signature.status {
        case .signed, .adHoc: return "保留 entitlements / flags，重建设计要求"
        case .unsigned: return "当前无现有签名"
        case .invalid: return "现有签名无效，将重建"
        case .unsupported: return "不适用"
        }
    }

    var commandPreview: String? {
        guard let target else { return nil }
        return QuickSigner.displayCommand(
            target: target,
            identity: selectedIdentity,
            options: options,
            hasExistingSignature: hasExistingSignature
        )
    }

    var canResign: Bool {
        guard let target, let signature else { return false }
        return target.canCodesign && signature.status != .unsupported && !isSigning && !isLoading
    }

    init() {
        activity = [
            LogEntry(level: .info, message: "Seal 已就绪", command: nil)
        ]
        Task { await loadIdentities(silent: true) }

        let args = CommandLine.arguments
        let inspectPath: String? = {
            if let index = args.firstIndex(of: "--inspect"), args.indices.contains(index + 1) {
                return args[index + 1]
            }
            return args.dropFirst().first(where: { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) })
        }()

        if let inspectPath, FileManager.default.fileExists(atPath: inspectPath) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                self?.select(url: URL(fileURLWithPath: inspectPath))
            }
        }

        if let index = args.firstIndex(of: "--tab"), args.indices.contains(index + 1),
           let tab = InspectorTab(rawValue: args[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.activeTab = tab
            }
        }
    }

    // MARK: - Selection

    func select(url: URL) {
        guard !isSigning else {
            showToast("签名进行中，请稍候", style: .info)
            return
        }
        let standardized = url.standardizedFileURL
        do {
            let info = try TargetInfo.make(url: standardized, calculateDirectorySize: false)
            inspectionID = UUID()
            target = info
            signature = nil
            xattrs = []
            options.deep = info.isCodeBundle
            options.preserveMetadata = true
            errorMessage = nil
            activeTab = .resign
            lastUpdated = nil
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                isDropTargeted = false
            }
            let id = inspectionID
            if info.isDirectory {
                let sizeURL = info.url
                Task {
                    let size = await Task.detached(priority: .utility) {
                        TargetInfo.directorySize(of: sizeURL)
                    }.value
                    guard self.target?.url == sizeURL else { return }
                    self.target?.byteSize = size
                }
            }
            Task { await refreshAll(expected: id) }
        } catch {
            errorMessage = error.localizedDescription
            showToast("无法读取这个文件", style: .error)
        }
    }

    func clearSelection() {
        guard !isSigning else { return }
        inspectionID = UUID()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            target = nil
            signature = nil
            xattrs = []
            errorMessage = nil
            lastUpdated = nil
        }
    }

    func refresh() {
        guard target != nil, !isSigning else { return }
        inspectionID = UUID()
        let id = inspectionID
        Task { await refreshAll(expected: id) }
    }

    private func refreshAll(expected id: UUID) async {
        guard let target else { return }
        isLoading = true
        defer {
            if inspectionID == id { isLoading = false }
        }

        async let signatureTask = SignatureInspector.inspect(target: target)

        let xattrResult: Result<[XattrItem], Error>
        do {
            xattrResult = .success(try await Task.detached(priority: .userInitiated) {
                try XattrService.list(at: target.url)
            }.value)
        } catch {
            xattrResult = .failure(error)
        }

        let report = await signatureTask
        guard inspectionID == id, self.target?.url == target.url else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            self.signature = report
            switch xattrResult {
            case .success(let items):
                self.xattrs = items
            case .failure(let error):
                self.xattrs = []
                self.log("扩展属性读取失败：\(error.localizedDescription)", level: .warning)
            }
            self.lastUpdated = Date()
        }

        if case .failure(let error) = xattrResult {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Identities

    func loadIdentities(silent: Bool = false) async {
        guard !isLoadingIdentities else { return }
        isLoadingIdentities = true
        let result = await IdentityService.load()
        identities = result.identities
        identityNote = result.message

        if !identities.contains(where: { $0.id == selectedIdentityID }) {
            let certificate = identities.first(where: { !$0.isAdHoc })
            selectedIdentityID = hasLoadedIdentities
                ? (identities.first?.id ?? "-")
                : (certificate?.id ?? "-")
        } else if !hasLoadedIdentities, selectedIdentityID == "-",
                  let certificate = identities.first(where: { !$0.isAdHoc }) {
            selectedIdentityID = certificate.id
        }

        hasLoadedIdentities = true
        isLoadingIdentities = false

        if !silent {
            if let message = result.message {
                showToast(message, style: .info)
            } else {
                showToast("已刷新签名证书", style: .success)
            }
        }
    }

    func refreshIdentities() {
        Task { await loadIdentities(silent: false) }
    }

    // MARK: - Signing

    func resign() {
        guard let target, let signature, target.canCodesign, signature.status != .unsupported else { return }
        guard !isSigning else { return }

        let identity = selectedIdentity
        let optionsSnapshot = options
        let existing = signature.status.isSigned
        let command = QuickSigner.displayCommand(
            target: target,
            identity: identity,
            options: optionsSnapshot,
            hasExistingSignature: existing
        )

        isSigning = true
        errorMessage = nil
        log("开始重新签名 · \(identity.isAdHoc ? "Ad-hoc" : identity.name)", command: command, level: .info)

        Task {
            let result = await QuickSigner.sign(
                target: target,
                identity: identity,
                options: optionsSnapshot,
                hasExistingSignature: existing
            )

            if result.succeeded {
                log("codesign 完成", command: nil, level: .success)

                if optionsSnapshot.removeQuarantine {
                    do {
                        try XattrService.remove(name: "com.apple.quarantine", at: target.url)
                        log("已移除 com.apple.quarantine", level: .info)
                    } catch {
                        log("移除隔离属性失败：\(error.localizedDescription)", level: .warning)
                    }
                }

                await refreshAll(expected: inspectionID)
                isSigning = false
                showToast("重新签名完成", style: .success)
            } else {
                let message = friendlySignError(result)
                errorMessage = message
                log(friendlySignError(result), command: result.combined, level: .error)
                isSigning = false
                showToast("签名失败", style: .error)
            }
        }
    }

    func verifySignature() {
        guard let target, !isVerifying, !isSigning else { return }
        isVerifying = true
        let command = CommandRunner.commandDisplay(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=4", target.url.path]
        )
        log("验证签名", command: command, level: .info)

        Task {
            let result = await CommandRunner.run(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", "--verbose=4", target.url.path]
            )
            if result.succeeded {
                log("codesign 校验通过", level: .success)
                showToast("签名校验通过", style: .success)
            } else {
                log("codesign 校验失败：\(result.combined)", level: .error)
                errorMessage = result.combined.isEmpty ? "签名校验失败。" : result.combined
                showToast("签名校验未通过", style: .error)
            }
            await refreshAll(expected: inspectionID)
            isVerifying = false
        }
    }

    private func friendlySignError(_ result: CommandResult) -> String {
        let output = result.combined
        if output.localizedCaseInsensitiveContains("resource fork, Finder information, or similar detritus not allowed") {
            return "codesign 发现文件带有阻断签名的扩展属性（FinderInfo 或资源分支）。请到「扩展属性」页移除后再试。"
        }
        if output.localizedCaseInsensitiveContains("no identity found") {
            return "没有找到可用的签名身份。请检查钥匙串中的代码签名证书。"
        }
        if output.localizedCaseInsensitiveContains("code object is not signed at all") {
            return output
        }
        return output.isEmpty ? "codesign 执行失败（退出码 \(result.status)）。" : output
    }

    // MARK: - xattr operations

    func removeXattr(_ item: XattrItem) {
        guard let target, !isWorkingXattrs else { return }
        isWorkingXattrs = true
        do {
            try XattrService.remove(name: item.name, at: target.url)
            log("已移除扩展属性 \(item.name)", level: .success)
            refreshXattrs()
            showToast("已移除 \(item.name)", style: .success)
        } catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, level: .error)
            showToast("移除失败", style: .error)
        }
        isWorkingXattrs = false
    }

    func removeQuarantine() {
        guard let target, !isWorkingXattrs else { return }
        isWorkingXattrs = true
        do {
            try XattrService.remove(name: "com.apple.quarantine", at: target.url)
            log("已移除隔离属性", level: .success)
            refreshXattrs()
            showToast("已移除隔离属性", style: .success)
        } catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, level: .error)
            showToast("移除失败", style: .error)
        }
        isWorkingXattrs = false
    }

    func clearAllXattrs() {
        guard let target, !isWorkingXattrs, !xattrs.isEmpty else { return }
        isWorkingXattrs = true
        clearAllConfirmation = false
        let names = xattrs.map(\.name)
        let recursive = xattrRecursive
        let targetURL = target.url
        Task {
            let summary = await Task.detached(priority: .userInitiated) {
                XattrService.remove(names: names, at: targetURL, recursive: recursive)
            }.value
            guard self.target?.url == targetURL else {
                self.isWorkingXattrs = false
                return
            }
            if summary.errors.isEmpty {
                self.log("已清除 \(summary.removed) 个扩展属性", level: .success)
                self.showToast("已清除 \(summary.removed) 个扩展属性", style: .success)
            } else {
                self.errorMessage = summary.errors.prefix(4).joined(separator: "\n")
                self.log("清除扩展属性时遇到问题：\(summary.errors.joined(separator: "；"))", level: .warning)
                self.showToast("部分扩展属性未能移除", style: .error)
            }
            self.refreshXattrs()
            self.isWorkingXattrs = false
        }
    }

    private func refreshXattrs() {
        guard let target else { return }
        do {
            let items = try XattrService.list(at: target.url)
            withAnimation(.easeOut(duration: 0.18)) {
                xattrs = items
                lastUpdated = Date()
            }
        } catch {
            log("扩展属性刷新失败：\(error.localizedDescription)", level: .warning)
        }
    }

    // MARK: - Entitlements

    func chooseEntitlements() {
        let panel = NSOpenPanel()
        panel.title = "选择 Entitlements 文件"
        panel.message = "选择一个 .plist 或 .entitlements 文件，签名时会传给 codesign。"
        panel.prompt = "使用"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            options.entitlementsPath = url
            log("已选择 Entitlements：\(url.path)", level: .info)
        }
    }

    func clearEntitlements() {
        options.entitlementsPath = nil
    }

    // MARK: - Panels & clipboard

    func openFilePanel() {
        guard !isSigning else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要检查的文件"
        panel.message = "拖入 App、Framework、插件或任意 Mach-O 二进制，也可以选择普通文件查看 xattr。"
        panel.prompt = "检查"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            select(url: url)
        }
    }

    func revealInFinder() {
        guard let target else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target.url])
    }

    func copyCommand() {
        guard let commandPreview else { return }
        copyToPasteboard(commandPreview)
        showToast("命令已复制", style: .info)
    }

    func copyLog() {
        let text = activity.map { entry in
            var line = "[\(Self.timeFormatter.string(from: entry.date))] \(entry.message)"
            if let command = entry.command {
                line += "\n\(command)"
            }
            return line
        }.joined(separator: "\n\n")
        copyToPasteboard(text)
        showToast("活动日志已复制", style: .info)
    }

    func copyReport() {
        guard let target, let signature else { return }
        var lines: [String] = [
            "Seal 检查报告",
            "路径：\(target.url.path)",
            "类型：\(target.kind.label)",
            "状态：\(signature.status.title)",
            "Identifier：\(signature.identifier ?? "—")",
            "Team ID：\(signature.teamID ?? "—")",
            "Authority：\(signature.authorities.joined(separator: " → "))",
            "CDHash：\(signature.cdhash ?? "—")",
            "Gatekeeper：\(signature.gatekeeper.title)",
            "校验：\(signature.verificationTitle)"
        ]
        if let entitlements = signature.entitlements {
            lines.append("Entitlements：\n\(entitlements)")
        }
        copyToPasteboard(lines.joined(separator: "\n"))
        showToast("检查报告已复制", style: .info)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - Helpers

    func log(_ message: String, command: String? = nil, level: LogLevel = .info) {
        let entry = LogEntry(level: level, message: message, command: command)
        withAnimation(.easeOut(duration: 0.18)) {
            activity.append(entry)
            if activity.count > 100 {
                activity.removeFirst(activity.count - 100)
            }
        }
    }

    func showToast(_ text: String, style: ToastStyle = .success) {
        let newToast = ToastMessage(text: text, style: style)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            toast = newToast
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard toast?.id == newToast.id else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                toast = nil
            }
        }
    }

    func dismissError() {
        withAnimation(.easeOut(duration: 0.2)) {
            errorMessage = nil
        }
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
