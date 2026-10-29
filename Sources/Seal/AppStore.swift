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
    @Published var batchItems: [BatchItem] = []
    @Published var showBatch = false
    @Published var batchRunning = false
    @Published var batchStopRequested = false
    @Published var batchProgress: Double = 0

    private var inspectionID = UUID()
    private var hasLoadedIdentities = false

    var selectedIdentity: SigningIdentity {
        identities.first(where: { $0.id == selectedIdentityID }) ?? .adHoc
    }

    var hasExistingSignature: Bool {
        signature?.status.isSigned == true
    }

    var signatureStateText: String {
        guard let signature else { return L10n.t("签名尚未读取") }
        switch signature.status {
        case .signed, .adHoc: return L10n.t("保留 entitlements / flags，重建设计要求")
        case .unsigned: return L10n.t("当前无现有签名")
        case .invalid: return L10n.t("现有签名无效，将重建")
        case .unsupported: return L10n.t("不适用")
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

    var batchSignedCount: Int { batchItems.filter { $0.state == .signed }.count }
    var batchFailedCount: Int { batchItems.filter { $0.state == .failed }.count }
    var batchSkippedCount: Int { batchItems.filter { $0.state == .skipped }.count }
    var batchReadyCount: Int { batchItems.filter { $0.state == .ready }.count }
    var batchPendingCount: Int { batchItems.filter { !$0.state.isCompleted && $0.state != .ready }.count }
    var batchEligibleCount: Int {
        batchItems.filter { $0.target.canCodesign && $0.state != .skipped }.count
    }
    var batchCanInspect: Bool { !batchItems.isEmpty && !batchRunning }
    var batchCanSign: Bool { !batchItems.isEmpty && !batchRunning && batchEligibleCount > 0 }
    var batchFraction: Double {
        guard !batchItems.isEmpty else { return 0 }
        let done = batchItems.filter { $0.state.isCompleted }.count
        return Double(done) / Double(batchItems.count)
    }

    init() {
        activity = [
            LogEntry(level: .info, message: L10n.t("Seal 已就绪"), command: nil)
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

        let batchPaths = args.indices.compactMap { index -> String? in
            guard args[index] == "--batch", args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let batchURLs = batchPaths.map { URL(fileURLWithPath: $0) }.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if !batchURLs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.addToBatch(batchURLs)
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
        guard !isSigning, !batchRunning else {
            showToast(L10n.t("签名进行中，请稍候"), style: .info)
            return
        }
        showBatch = false
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
            showToast(L10n.t("无法读取这个文件"), style: .error)
        }
    }

    func clearSelection() {
        guard !isSigning, !batchRunning else { return }
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

    func refreshCurrent() {
        if showBatch {
            inspectBatch()
        } else {
            refresh()
        }
    }

    // MARK: - Batch

    var batchProgressValue: Double {
        batchFraction
    }

    func toggleBatchMode() {
        guard !batchRunning else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            showBatch.toggle()
        }
    }

    func closeBatch() {
        guard !batchRunning else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            showBatch = false
        }
    }

    func handleDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count > 1 || showBatch {
            addToBatch(urls)
        } else {
            select(url: urls[0])
        }
    }

    func addToBatch(_ urls: [URL]) {
        guard !batchRunning else {
            showToast(L10n.t("批量操作进行中，请稍候"), style: .info)
            return
        }
        let existing = Set(batchItems.map { $0.target.url.path })
        var addedIDs: [UUID] = []
        var seen = existing

        for url in urls {
            let standardized = url.standardizedFileURL
            guard !seen.contains(standardized.path) else { continue }
            do {
                let target = try TargetInfo.make(url: standardized, calculateDirectorySize: false)
                seen.insert(standardized.path)
                let item = BatchItem(target: target)
                batchItems.append(item)
                addedIDs.append(item.id)

                if target.isDirectory {
                    Task {
                        let size = await Task.detached(priority: .utility) {
                            TargetInfo.directorySize(of: target.url)
                        }.value
                        guard let index = self.batchItems.firstIndex(where: { $0.id == item.id }) else { return }
                        self.batchItems[index].target.byteSize = size
                    }
                }
            } catch {
                log(L10n.t("无法读取文件：%@", standardized.path), level: .error)
            }
        }

        guard !addedIDs.isEmpty else {
            showBatch = true
            showToast(L10n.t("没有新增文件"), style: .info)
            return
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            showBatch = true
        }
        batchProgress = 0
        Task { await runInspection(ids: addedIDs) }
    }

    func inspectBatch() {
        guard batchCanInspect else { return }
        let ids = batchItems.map(\.id)
        Task { await runInspection(ids: ids) }
    }

    private func runInspection(ids: [UUID]) async {
        guard !ids.isEmpty, !batchRunning else { return }
        batchRunning = true
        batchStopRequested = false
        batchProgress = 0
        var processed = 0
        let total = ids.count
        log(L10n.t("批量检查开始 · %d 项", total), level: .info)

        for id in ids {
            if batchStopRequested { break }
            guard let index = batchItems.firstIndex(where: { $0.id == id }) else {
                processed += 1
                continue
            }
            batchItems[index].state = .inspecting
            batchItems[index].message = L10n.t("正在读取签名…")
            let target = batchItems[index].target
            let report = await SignatureInspector.inspect(target: target)

            guard let freshIndex = batchItems.firstIndex(where: { $0.id == id }) else {
                processed += 1
                continue
            }
            batchItems[freshIndex].report = report
            batchItems[freshIndex].state = report.status == .unsupported ? .skipped : .ready
            batchItems[freshIndex].message = report.status.title
            batchItems[freshIndex].lastUpdated = Date()
            processed += 1
            batchProgress = Double(processed) / Double(total)
        }

        let stopped = batchStopRequested
        batchRunning = false
        batchStopRequested = false
        batchProgress = Double(processed) / Double(max(total, 1))

        if stopped {
            log(L10n.t("批量检查已停止"), level: .warning)
            showToast(L10n.t("批量检查已停止"), style: .info)
        } else {
            log(L10n.t("批量检查完成"), level: .success)
            showToast(L10n.t("批量检查完成"), style: .success)
        }
    }

    func signBatch() {
        guard batchCanSign else { return }
        let ids = batchItems
            .filter { $0.target.canCodesign && $0.state != .skipped }
            .map(\.id)
        guard !ids.isEmpty else {
            showToast(L10n.t("没有可签名的项目"), style: .info)
            return
        }
        Task { await runSigning(ids: ids) }
    }

    func signBatchItem(_ id: UUID) {
        guard !batchRunning, let item = batchItems.first(where: { $0.id == id }), item.target.canCodesign else { return }
        Task { await runSigning(ids: [id]) }
    }

    private func runSigning(ids: [UUID]) async {
        guard !ids.isEmpty, !batchRunning else { return }
        let identity = selectedIdentity
        let optionsSnapshot = options
        batchRunning = true
        batchStopRequested = false
        batchProgress = 0
        var processed = 0
        var successCount = 0
        var failureCount = 0
        let total = ids.count
        log(L10n.t("批量签名开始 · %d 项", total), level: .info)

        for id in ids {
            if batchStopRequested { break }
            guard let index = batchItems.firstIndex(where: { $0.id == id }) else {
                processed += 1
                continue
            }
            guard batchItems[index].target.canCodesign else {
                batchItems[index].state = .skipped
                batchItems[index].message = L10n.t("不可签名")
                processed += 1
                batchProgress = Double(processed) / Double(total)
                continue
            }

            let target = batchItems[index].target
            let name = target.displayName
            let existing = batchItems[index].report?.status.isSigned == true
            batchItems[index].state = .signing
            batchItems[index].message = L10n.t("正在签名…")
            batchItems[index].lastUpdated = Date()

            let result = await QuickSigner.sign(
                target: target,
                identity: identity,
                options: optionsSnapshot,
                hasExistingSignature: existing
            )

            if result.succeeded {
                if optionsSnapshot.removeQuarantine {
                    do {
                        try XattrService.remove(name: "com.apple.quarantine", at: target.url)
                    } catch {
                        log(L10n.t("移除隔离属性失败：%@", error.localizedDescription), level: .warning)
                    }
                }

                let report = await SignatureInspector.inspect(target: target)
                guard let freshIndex = batchItems.firstIndex(where: { $0.id == id }) else {
                    processed += 1
                    continue
                }
                batchItems[freshIndex].report = report
                batchItems[freshIndex].lastUpdated = Date()
                if report.status.isSigned {
                    batchItems[freshIndex].state = .signed
                    batchItems[freshIndex].message = report.status.title
                    successCount += 1
                    log(L10n.t("签名完成：%@", name), level: .success)
                } else {
                    batchItems[freshIndex].state = .failed
                    batchItems[freshIndex].message = report.verificationOutput.isEmpty
                        ? L10n.t("签名后校验失败")
                        : report.verificationOutput
                    failureCount += 1
                    log(L10n.t("签名后校验失败：%@", name), level: .error)
                }
            } else {
                guard let freshIndex = batchItems.firstIndex(where: { $0.id == id }) else {
                    processed += 1
                    continue
                }
                batchItems[freshIndex].state = .failed
                batchItems[freshIndex].message = friendlySignError(result)
                batchItems[freshIndex].lastUpdated = Date()
                failureCount += 1
                log(L10n.t("签名失败：%@", name), command: result.combined, level: .error)
            }

            processed += 1
            batchProgress = Double(processed) / Double(total)
        }

        let stopped = batchStopRequested
        batchRunning = false
        batchStopRequested = false
        batchProgress = Double(processed) / Double(max(total, 1))

        if stopped {
            log(L10n.t("批量签名已停止"), level: .warning)
            showToast(L10n.t("批量签名已停止"), style: .info)
        } else {
            log(L10n.t("批量签名完成 · 成功 %d / 失败 %d", successCount, failureCount), level: .success)
            showToast(L10n.t("批量签名完成 · 成功 %d / 失败 %d", successCount, failureCount), style: .success)
        }
    }

    func stopBatch() {
        guard batchRunning else { return }
        batchStopRequested = true
        log(L10n.t("正在停止批量操作…"), level: .warning)
        showToast(L10n.t("正在停止批量操作…"), style: .info)
    }

    func removeBatchItem(_ id: UUID) {
        guard !batchRunning else { return }
        batchItems.removeAll { $0.id == id }
        if batchItems.isEmpty { batchProgress = 0 }
    }

    func clearBatch(completedOnly: Bool = false) {
        guard !batchRunning else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            if completedOnly {
                batchItems.removeAll { $0.state == .signed || $0.state == .failed || $0.state == .skipped }
            } else {
                batchItems.removeAll()
            }
            if batchItems.isEmpty { batchProgress = 0 }
        }
    }

    func openBatchItemInSingleView(_ id: UUID) {
        guard !batchRunning, let item = batchItems.first(where: { $0.id == id }) else { return }
        select(url: item.target.url)
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
                self.log(L10n.t("扩展属性读取失败：%@", error.localizedDescription), level: .warning)
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
                showToast(L10n.t("已刷新签名证书"), style: .success)
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
        log(L10n.t("开始重新签名 · %@", identity.displayName), command: command, level: .info)

        Task {
            let result = await QuickSigner.sign(
                target: target,
                identity: identity,
                options: optionsSnapshot,
                hasExistingSignature: existing
            )

            if result.succeeded {
                log(L10n.t("codesign 完成"), command: nil, level: .success)

                if optionsSnapshot.removeQuarantine {
                    do {
                        try XattrService.remove(name: "com.apple.quarantine", at: target.url)
                        log(L10n.t("已移除 com.apple.quarantine"), level: .info)
                    } catch {
                        log(L10n.t("移除隔离属性失败：%@", error.localizedDescription), level: .warning)
                    }
                }

                await refreshAll(expected: inspectionID)
                isSigning = false
                showToast(L10n.t("重新签名完成"), style: .success)
            } else {
                let message = friendlySignError(result)
                errorMessage = message
                log(friendlySignError(result), command: result.combined, level: .error)
                isSigning = false
                showToast(L10n.t("签名失败"), style: .error)
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
        log(L10n.t("验证签名"), command: command, level: .info)

        Task {
            let result = await CommandRunner.run(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", "--verbose=4", target.url.path]
            )
            if result.succeeded {
                log(L10n.t("codesign 校验通过"), level: .success)
                showToast(L10n.t("签名校验通过"), style: .success)
            } else {
                log(L10n.t("codesign 校验失败：%@", result.combined), level: .error)
                errorMessage = result.combined.isEmpty ? L10n.t("签名校验失败。") : result.combined
                showToast(L10n.t("签名校验未通过"), style: .error)
            }
            await refreshAll(expected: inspectionID)
            isVerifying = false
        }
    }

    private func friendlySignError(_ result: CommandResult) -> String {
        let output = result.combined
        if output.localizedCaseInsensitiveContains("resource fork, Finder information, or similar detritus not allowed") {
            return L10n.t("codesign 发现文件带有阻断签名的扩展属性（FinderInfo 或资源分支）。请到「扩展属性」页移除后再试。")
        }
        if output.localizedCaseInsensitiveContains("no identity found") {
            return L10n.t("没有找到可用的签名身份。请检查钥匙串中的代码签名证书。")
        }
        if output.localizedCaseInsensitiveContains("code object is not signed at all") {
            return output
        }
        return output.isEmpty ? L10n.t("codesign 执行失败（退出码 %d）。", result.status) : output
    }

    // MARK: - xattr operations

    func removeXattr(_ item: XattrItem) {
        guard let target, !isWorkingXattrs else { return }
        isWorkingXattrs = true
        do {
            try XattrService.remove(name: item.name, at: target.url)
            log(L10n.t("已移除扩展属性 %@", item.name), level: .success)
            refreshXattrs()
            showToast(L10n.t("已移除 %@", item.name), style: .success)
        } catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, level: .error)
            showToast(L10n.t("移除失败"), style: .error)
        }
        isWorkingXattrs = false
    }

    func removeQuarantine() {
        guard let target, !isWorkingXattrs else { return }
        isWorkingXattrs = true
        do {
            try XattrService.remove(name: "com.apple.quarantine", at: target.url)
            log(L10n.t("已移除隔离属性"), level: .success)
            refreshXattrs()
            showToast(L10n.t("已移除隔离属性"), style: .success)
        } catch {
            errorMessage = error.localizedDescription
            log(error.localizedDescription, level: .error)
            showToast(L10n.t("移除失败"), style: .error)
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
                self.log(L10n.t("已清除 %d 个扩展属性", summary.removed), level: .success)
                self.showToast(L10n.t("已清除 %d 个扩展属性", summary.removed), style: .success)
            } else {
                self.errorMessage = summary.errors.prefix(4).joined(separator: "\n")
                self.log(L10n.t("清除扩展属性时遇到问题：%@", summary.errors.joined(separator: "；")), level: .warning)
                self.showToast(L10n.t("部分扩展属性未能移除"), style: .error)
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
            log(L10n.t("扩展属性刷新失败：%@", error.localizedDescription), level: .warning)
        }
    }

    // MARK: - Entitlements

    func chooseEntitlements() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("选择 Entitlements 文件")
        panel.message = L10n.t("选择一个 .plist 或 .entitlements 文件，签名时会传给 codesign。")
        panel.prompt = L10n.t("使用")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            options.entitlementsPath = url
            log(L10n.t("已选择 Entitlements：%@", url.path), level: .info)
        }
    }

    func clearEntitlements() {
        options.entitlementsPath = nil
    }

    // MARK: - Panels & clipboard

    func openFilePanel() {
        guard !isSigning, !batchRunning else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.t("选择要检查的文件")
        panel.message = L10n.t("支持多选；选择多个文件会加入批量队列。")
        panel.prompt = showBatch ? L10n.t("添加") : L10n.t("检查")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            let urls = panel.urls
            if urls.count > 1 || showBatch {
                addToBatch(urls)
            } else if let url = urls.first {
                select(url: url)
            }
        }
    }

    func revealInFinder() {
        guard let target else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target.url])
    }

    func revealBatchItem(_ id: UUID) {
        guard let item = batchItems.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.target.url])
    }

    func copyCommand() {
        guard let commandPreview else { return }
        copyToPasteboard(commandPreview)
        showToast(L10n.t("命令已复制"), style: .info)
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
        showToast(L10n.t("活动日志已复制"), style: .info)
    }

    func copyReport() {
        guard let target, let signature else { return }
        var lines: [String] = [
            L10n.t("Seal 检查报告"),
            L10n.t("路径：%@", target.url.path),
            L10n.t("类型：%@", target.kind.label),
            L10n.t("状态：%@", signature.status.title),
            "Identifier：\(signature.identifier ?? "—")",
            "Team ID：\(signature.teamID ?? "—")",
            "Authority：\(signature.authorities.joined(separator: " → "))",
            "CDHash：\(signature.cdhash ?? "—")",
            "Gatekeeper：\(signature.gatekeeper.title)",
            L10n.t("校验：%@", signature.verificationTitle)
        ]
        if let entitlements = signature.entitlements {
            lines.append("Entitlements：\n\(entitlements)")
        }
        copyToPasteboard(lines.joined(separator: "\n"))
        showToast(L10n.t("检查报告已复制"), style: .info)
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
