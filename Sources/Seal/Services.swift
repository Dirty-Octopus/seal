import Foundation
import Darwin

// MARK: - Identities

struct IdentityLoadResult {
    let identities: [SigningIdentity]
    let message: String?
}

enum IdentityService {
    static func load() async -> IdentityLoadResult {
        let result = await CommandRunner.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        var identities: [SigningIdentity] = []
        let pattern = #"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.*)"\s*$"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in result.combined.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            guard let regex,
                  let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                  match.numberOfRanges == 3 else { continue }
            let hash = nsLine.substring(with: match.range(at: 1))
            let name = nsLine.substring(with: match.range(at: 2))
            identities.append(SigningIdentity(id: hash, name: name, isAdHoc: false))
        }

        let message: String?
        if result.status != 0 {
            message = result.combined.isEmpty ? "无法读取代码签名证书。" : result.combined
        } else if identities.isEmpty {
            message = "未发现可用的代码签名证书，将使用 Ad-hoc 签名。"
        } else {
            message = nil
        }

        identities.append(.adHoc)
        return IdentityLoadResult(identities: identities, message: message)
    }
}

// MARK: - Signature inspection

enum SignatureInspector {
    static func inspect(target: TargetInfo) async -> SignatureReport {
        guard target.canCodesign else {
            var report = SignatureReport()
            report.status = .unsupported
            report.verificationOutput = "普通文件夹不包含可签名代码。扩展属性仍可正常读写。"
            report.verificationPassed = false
            report.gatekeeper = .notAssessed("普通文件夹不参与 Gatekeeper 评估")
            return report
        }

        let path = target.url.path
        async let displayTask = CommandRunner.run("/usr/bin/codesign", ["-dvvv", path])
        async let verifyTask = CommandRunner.run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", path]
        )
        let (display, verify) = await (displayTask, verifyTask)

        var report = SignatureReport()
        report.rawDisplay = display.combined
        report.verificationOutput = verify.combined
        report.verificationPassed = verify.status == 0

        let displayText = display.combined
        let notSigned = displayText.localizedCaseInsensitiveContains("not signed at all")
            || displayText.localizedCaseInsensitiveContains("code object is not signed")

        if display.status != 0 {
            report.status = notSigned ? .unsigned : .invalid
            if report.verificationOutput.isEmpty {
                report.verificationOutput = displayText
            }
            report.gatekeeper = .notAssessed(notSigned ? "未签名对象不参与 Gatekeeper 评估" : "签名无效，未执行 Gatekeeper 评估")
            return report
        }

        parse(displayText, into: &report)
        let isAdHoc = displayText.localizedCaseInsensitiveContains("Signature=adhoc")
        if verify.status == 0 {
            report.status = isAdHoc ? .adHoc : .signed
        } else {
            report.status = .invalid
            report.verificationPassed = false
        }

        async let entitlementTask = CommandRunner.run(
            "/usr/bin/codesign",
            ["-d", "--entitlements", ":-", path]
        )
        let gatekeeperTask: Task<CommandResult?, Never>? = target.kind == .appBundle
            ? Task {
                await CommandRunner.run(
                    "/usr/sbin/spctl",
                    ["--assess", "--type", "execute", "--verbose=4", path]
                )
            }
            : nil

        let entitlement = await entitlementTask
        if entitlement.status == 0, !entitlement.combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report.entitlements = extractPlist(from: entitlement.combined)
        }

        if let gatekeeperTask, let gatekeeper = await gatekeeperTask.value {
            if gatekeeper.status == 0 {
                report.gatekeeper = .accepted
            } else {
                let lines = gatekeeper.combined
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix(path) }
                report.gatekeeper = .rejected(lines.prefix(3).joined(separator: " · "))
            }
        } else if target.kind != .appBundle {
            report.gatekeeper = .notAssessed("仅对 App Bundle 做 Gatekeeper 评估")
        }

        return report
    }

    private static func parse(_ text: String, into report: inout SignatureReport) {
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("Identifier=") {
                report.identifier = value(after: "Identifier=", in: line)
            } else if line.hasPrefix("Format=") {
                report.format = value(after: "Format=", in: line)
            } else if line.hasPrefix("Authority=") {
                let authority = value(after: "Authority=", in: line)
                if let authority, !authority.isEmpty, authority != "(unavailable)" {
                    report.authorities.append(authority)
                }
            } else if line.hasPrefix("TeamIdentifier=") {
                let team = value(after: "TeamIdentifier=", in: line)
                report.teamID = (team == nil || team == "not set") ? nil : team
            } else if line.hasPrefix("CDHash=") {
                report.cdhash = value(after: "CDHash=", in: line)
            } else if line.hasPrefix("Timestamp=") {
                report.timestamp = value(after: "Timestamp=", in: line)
            } else if line.hasPrefix("Signature size=") {
                report.signatureSize = value(after: "Signature size=", in: line)
            } else if line.contains("flags=0x") {
                report.flags = parseFlags(from: line).labels
            }
        }

        if report.authorities.isEmpty {
            report.authorities = []
        }
    }

    private static func parseFlags(from line: String) -> (value: UInt64, labels: [String]) {
        guard let range = line.range(of: "flags=") else { return (0, []) }
        let tail = line[range.upperBound...]
        let token = tail.prefix { !$0.isWhitespace }
        let parts = token.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
        let hex = parts.first.map(String.init) ?? "0x0"
        let value = UInt64(hex.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
        var labels: [String] = []

        if parts.count > 1 {
            let inner = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: ")"))
            labels.append(contentsOf: inner.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        }
        if value & 0x2 != 0, !labels.contains("adhoc") { labels.append("adhoc") }
        if value & 0x10000 != 0, !labels.contains("runtime") { labels.append("runtime") }
        if value & 0x20000 != 0, !labels.contains("linker-signed") { labels.append("linker-signed") }
        return (value, labels)
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func extractPlist(from text: String) -> String {
        if let range = text.range(of: "<?xml") {
            return String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = text.range(of: "<plist") {
            return String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Re-signing

enum QuickSigner {
    static func arguments(
        target: TargetInfo,
        identity: SigningIdentity,
        options: SignOptions,
        hasExistingSignature: Bool
    ) -> [String] {
        var args: [String] = []

        if options.force {
            args.append("--force")
        }
        if options.deep, target.isCodeBundle {
            args.append("--deep")
        }
        if options.preserveMetadata, hasExistingSignature {
            args.append("--preserve-metadata=entitlements,flags,runtime")
        }
        if options.hardenedRuntime {
            args.append("--options")
            args.append("runtime")
        }
        if !identity.isAdHoc {
            args.append(options.timestamp ? "--timestamp" : "--timestamp=none")
        }
        if let entitlements = options.entitlementsPath,
           FileManager.default.fileExists(atPath: entitlements.path) {
            args.append("--entitlements")
            args.append(entitlements.path)
        }

        args.append("--sign")
        args.append(identity.id)
        args.append(target.url.path)
        return args
    }

    static func sign(
        target: TargetInfo,
        identity: SigningIdentity,
        options: SignOptions,
        hasExistingSignature: Bool
    ) async -> CommandResult {
        let args = arguments(
            target: target,
            identity: identity,
            options: options,
            hasExistingSignature: hasExistingSignature
        )
        return await CommandRunner.run("/usr/bin/codesign", args)
    }

    static func displayCommand(
        target: TargetInfo,
        identity: SigningIdentity,
        options: SignOptions,
        hasExistingSignature: Bool
    ) -> String {
        CommandRunner.commandDisplay(
            "/usr/bin/codesign",
            arguments(
                target: target,
                identity: identity,
                options: options,
                hasExistingSignature: hasExistingSignature
            )
        )
    }
}

// MARK: - xattr

enum XattrService {
    static func list(at url: URL) throws -> [XattrItem] {
        let path = url.path
        let listSize = path.withCString { listxattr($0, nil, 0, XATTR_NOFOLLOW) }
        guard listSize >= 0 else {
            throw SealError.xattr("读取扩展属性失败：\(posixMessage())")
        }
        guard listSize > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: listSize)
        let readSize = path.withCString {
            listxattr($0, &buffer, listSize, XATTR_NOFOLLOW)
        }
        guard readSize >= 0 else {
            throw SealError.xattr("读取扩展属性失败：\(posixMessage())")
        }

        let data = Data(bytes: buffer, count: readSize)
        var names = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        names.sort { lhs, rhs in
            if lhs == "com.apple.quarantine" { return true }
            if rhs == "com.apple.quarantine" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        return try names.map { name in
            let value = try valueData(name: name, at: url)
            return XattrDecoder.make(name: name, data: value)
        }
    }

    static func valueData(name: String, at url: URL) throws -> Data {
        let path = url.path
        let size = path.withCString { cPath in
            name.withCString { cName in
                getxattr(cPath, cName, nil, 0, 0, XATTR_NOFOLLOW)
            }
        }
        guard size >= 0 else {
            throw SealError.xattr("读取 \(name) 失败：\(posixMessage())")
        }
        guard size > 0 else { return Data() }

        var buffer = [UInt8](repeating: 0, count: size)
        let readSize = path.withCString { cPath in
            name.withCString { cName in
                getxattr(cPath, cName, &buffer, size, 0, XATTR_NOFOLLOW)
            }
        }
        guard readSize >= 0 else {
            throw SealError.xattr("读取 \(name) 失败：\(posixMessage())")
        }
        return Data(buffer.prefix(readSize))
    }

    static func remove(name: String, at url: URL) throws {
        let path = url.path
        let result = path.withCString { cPath in
            name.withCString { cName in
                removexattr(cPath, cName, XATTR_NOFOLLOW)
            }
        }
        guard result == 0 else {
            if errno == ENOATTR { return }
            throw SealError.xattr("移除 \(name) 失败：\(posixMessage())")
        }
    }

    struct RemovalSummary {
        var removed = 0
        var errors: [String] = []
    }

    static func remove(
        names: [String],
        at url: URL,
        recursive: Bool
    ) -> RemovalSummary {
        var summary = RemovalSummary()
        var urls: [URL] = [url]
        if recursive, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                options: [],
                errorHandler: { _, _ in true }
            ) {
                while let child = enumerator.nextObject() as? URL {
                    urls.append(child)
                }
            }
        }

        for targetURL in urls {
            for name in names {
                let path = targetURL.path
                let result = path.withCString { cPath in
                    name.withCString { cName in
                        removexattr(cPath, cName, XATTR_NOFOLLOW)
                    }
                }
                if result == 0 {
                    summary.removed += 1
                } else if errno != ENOATTR {
                    summary.errors.append("\(targetURL.lastPathComponent): \(posixMessage())")
                }
            }
        }
        return summary
    }

    private static func posixMessage() -> String {
        String(cString: strerror(errno))
    }
}
