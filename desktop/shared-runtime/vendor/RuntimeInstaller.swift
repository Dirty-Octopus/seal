import Foundation
import AppKit
import CryptoKit
import Darwin

// No Electron/Node dependency: this executable runs before the runtime exists.
struct Entry: Codable { let path: String; let sha256: String?; let target: String? }
struct Manifest: Codable {
    let schema: Int
    let runtimeID: String
    let architecture: String
    let archiveURL: String
    let archiveSHA256: String
    let frameworks: [String]
    let files: [Entry]
    let appBundle: String
    let bundleID: String
    let appArchiveURL: String?
    let appArchiveSHA256: String?
    let developmentPreview: Bool?
}
struct Failure: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw Failure(description: message) }
}
let fm = FileManager.default
func hash(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var sha = SHA256()
    while let bytes = try file.read(upToCount: 1 << 20), !bytes.isEmpty { sha.update(data: bytes) }
    return sha.finalize().map { String(format: "%02x", $0) }.joined()
}
@discardableResult func run(_ binary: String, _ args: [String]) throws -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: binary); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    try require(p.terminationStatus == 0, "\(binary) failed (\(p.terminationStatus)): \(output)")
    return output
}
func safeRelative(_ value: String) -> Bool {
    !value.isEmpty && !value.hasPrefix("/") && !value.split(separator: "/").contains("..") && !value.contains("\0")
}
func attributes(_ url: URL) throws -> [FileAttributeKey: Any] { try fm.attributesOfItem(atPath: url.path) }
func safeDirectory(_ url: URL, production: Bool) throws {
    if !fm.fileExists(atPath: url.path) { try fm.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755]) }
    let a = try attributes(url)
    try require(a[.type] as? FileAttributeType == .typeDirectory, "Not a real directory: \(url.path)")
    if production {
        try require((a[.ownerAccountID] as? NSNumber)?.intValue == 0, "Directory is not owned by root: \(url.path)")
        try require(((a[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0, "Directory is writable by other users: \(url.path)")
    }
}
func entries(_ root: URL) throws -> [String] {
    guard let e = fm.enumerator(atPath: root.path) else { throw Failure(description: "Cannot enumerate \(root.path)") }
    var result: [String] = []
    for case let relative as String in e {
        let a = try attributes(root.appendingPathComponent(relative))
        if a[.type] as? FileAttributeType != .typeDirectory { result.append(relative) }
    }
    return result.sorted()
}
func verify(_ root: URL, _ m: Manifest) throws {
    let actual = Set(try entries(root)), expected = Set(m.files.map(\.path))
    try require(actual == expected, "Runtime file list mismatch; missing: \(expected.subtracting(actual).sorted().prefix(3)); extra: \(actual.subtracting(expected).sorted().prefix(3))")
    for entry in m.files {
        let file = root.appendingPathComponent(entry.path)
        let a = try attributes(file)
        if let target = entry.target {
            try require(a[.type] as? FileAttributeType == .typeSymbolicLink, "Expected symbolic link: \(entry.path)")
            try require(try fm.destinationOfSymbolicLink(atPath: file.path) == target, "Changed symbolic link: \(entry.path)")
            try require(file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"), "Escaping runtime link")
        } else {
            try require(a[.type] as? FileAttributeType == .typeRegular, "Not a regular runtime file: \(entry.path)")
            try require(try hash(file) == entry.sha256, "Runtime hash mismatch: \(entry.path)")
        }
    }
}
// Directory nodes are separate. Regular files share the same inode; symlinks stay internal.
func project(_ source: URL, _ target: URL) throws {
    let a = try attributes(source)
    switch a[.type] as? FileAttributeType {
    case .typeSymbolicLink:
        try fm.createSymbolicLink(atPath: target.path, withDestinationPath: fm.destinationOfSymbolicLink(atPath: source.path))
    case .typeDirectory:
        try fm.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        for name in try fm.contentsOfDirectory(atPath: source.path) { try project(source.appendingPathComponent(name), target.appendingPathComponent(name)) }
    case .typeRegular:
        // Fail on cross-volume installs rather than silently duplicating the runtime.
        try fm.linkItem(at: source, to: target)
    default: throw Failure(description: "Unsupported runtime node")
    }
}
func download(_ address: String, _ checksum: String, to archive: URL, testing: Bool) throws {
    guard let url = URL(string: address) else { throw Failure(description: "Invalid download URL") }
    let loopback = testing && ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    try require(url.scheme == "https" || (loopback && url.scheme == "http"), "Download requires HTTPS")
    try require(checksum.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, "Invalid pinned archive hash")
    try run("/usr/bin/curl", ["--fail", "--location", "--silent", "--show-error", "--proto", loopback ? "=http,https" : "=https", "--proto-redir", loopback ? "=http,https" : "=https", "--connect-timeout", "20", "--max-time", "600", "--retry", "2", "--output", archive.path, url.absoluteString])
    try require(try hash(archive) == checksum, "Downloaded archive checksum mismatch; installation aborted")
}
func attachApp(_ app: URL, runtime: URL, manifest m: Manifest, testing: Bool) throws {
    try safeDirectory(app, production: !testing)
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any] ?? [:]
    try require(info["CFBundleIdentifier"] as? String == m.bundleID, "Application bundle ID mismatch")
    let contents = app.appendingPathComponent("Contents")
    try safeDirectory(contents, production: !testing)
    let frameworks = contents.appendingPathComponent("Frameworks")
    try safeDirectory(frameworks, production: !testing)
    for name in m.frameworks {
        let target = frameworks.appendingPathComponent(name)
        // Only assemble a fresh thin bundle. Never rewrite an installed shared framework.
        try require(!fm.fileExists(atPath: target.path), "Application archive already contains a shared framework")
        try project(runtime.appendingPathComponent(name), target)
    }
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
}
func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    try require(args.count == 4, "Usage: aym-runtime-installer prepare|install|attach|verify manifest.json --volume / OR --test-root /isolated/path")
    let action = args[0], manifestURL = URL(fileURLWithPath: args[1])
    let testing = args[2] == "--test-root"
    try require(testing || args[2] == "--volume", "Unknown root mode")
    if testing {
        try require(geteuid() != 0, "Test mode must never run as root")
    } else {
        try require(geteuid() == 0, "Run production installation through macOS Installer")
        try require(args[3] == "/", "Only the active startup volume is supported")
    }
    let root = URL(fileURLWithPath: args[3], isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    if testing {
        try require(root.path != "/" && !root.path.hasPrefix("/Applications") && root.path != NSHomeDirectory(), "Unsafe test root")
        try require(fm.fileExists(atPath: root.appendingPathComponent(".aym-runtime-test-root").path), "Test root marker missing")
    }
    let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    try require(m.schema == 1 && m.runtimeID.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil, "Invalid runtime identity")
    try require(m.appBundle.hasSuffix(".app") && !m.appBundle.contains("/") && !m.appBundle.hasPrefix("."), "Invalid application name")
    try require(m.files.allSatisfy { safeRelative($0.path) } && Set(m.files.map(\.path)).count == m.files.count, "Invalid file manifest")
    try require(m.frameworks.allSatisfy { !$0.contains("/") && $0.hasSuffix(".framework") }, "Invalid framework list")
    #if arch(arm64)
    try require(m.architecture == "arm64", "This package requires another CPU architecture")
    #else
    try require(m.architecture == "x64", "This package requires another CPU architecture")
    #endif
    if action == "prepare" || action == "attach" || action == "install" {
        try require(!NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == m.bundleID }, "Quit this application before installing an update")
    }
    let apps = root.appendingPathComponent("Applications")
    if testing { try safeDirectory(apps, production: false) }
    let suite = apps.appendingPathComponent("Andy Yu")
    try safeDirectory(suite, production: !testing)
    let runtimes = suite.appendingPathComponent("Runtime")
    try safeDirectory(runtimes, production: !testing)
    let lockPath = runtimes.appendingPathComponent(".install.lock").path
    let lock = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    try require(lock >= 0, "Cannot open installation lock")
    defer { flock(lock, LOCK_UN); close(lock) }
    try require(flock(lock, LOCK_EX) == 0, "Cannot acquire installation lock")
    let runtime = runtimes.appendingPathComponent(m.runtimeID)
    if action == "prepare" {
        if fm.fileExists(atPath: runtime.path) {
            try safeDirectory(runtime, production: !testing)
            try verify(runtime, m)
            print("REUSED \(m.runtimeID)"); return
        }
        let stage = runtimes.appendingPathComponent(".download-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        let archive = stage.appendingPathComponent("runtime.zip")
        try download(m.archiveURL, m.archiveSHA256, to: archive, testing: testing)
        let extracted = stage.appendingPathComponent("extracted")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        try verify(extracted, m)
        for framework in m.frameworks { try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", extracted.appendingPathComponent(framework).path]) }
        // Never overwrite a published version. Existing installations keep their inodes.
        try fm.moveItem(at: extracted, to: runtime)
        print("DOWNLOADED \(m.runtimeID)")
    } else if action == "attach" {
        try safeDirectory(runtime, production: !testing)
        try verify(runtime, m)
        try attachApp(suite.appendingPathComponent(m.appBundle), runtime: runtime, manifest: m, testing: testing)
        print("ATTACHED \(m.appBundle)")
    } else if action == "install" {
        try safeDirectory(runtime, production: !testing)
        try verify(runtime, m)
        guard let url = m.appArchiveURL, let checksum = m.appArchiveSHA256 else { throw Failure(description: "Application download manifest missing") }
        let stage = suite.appendingPathComponent(".install-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let backup = stage.appendingPathComponent("previous.app")
        // Preserve a recoverable previous app if a filesystem error prevents rollback.
        defer { if !fm.fileExists(atPath: backup.path) { try? fm.removeItem(at: stage) } }
        let archive = stage.appendingPathComponent("application.zip")
        try download(url, checksum, to: archive, testing: testing)
        let extracted = stage.appendingPathComponent("payload")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let assembled = extracted.appendingPathComponent(m.appBundle)
        try attachApp(assembled, runtime: runtime, manifest: m, testing: testing)
        if m.developmentPreview != true {
            try run("/usr/sbin/spctl", ["--assess", "--type", "execute", assembled.path])
        }
        let target = suite.appendingPathComponent(m.appBundle)
        let replacing = fm.fileExists(atPath: target.path)
        if replacing {
            try safeDirectory(target, production: !testing)
            let previousInfo = try PropertyListSerialization.propertyList(from: Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any] ?? [:]
            try require(previousInfo["CFBundleIdentifier"] as? String == m.bundleID, "Another application already occupies the installation path")
            try fm.moveItem(at: target, to: backup)
        }
        do { try fm.moveItem(at: assembled, to: target) }
        catch {
            if replacing { try fm.moveItem(at: backup, to: target) }
            throw error
        }
        if replacing { try fm.removeItem(at: backup) }
        print("INSTALLED \(m.appBundle)")
    } else if action == "verify" {
        try verify(runtime, m); print("VERIFIED \(m.runtimeID)")
    } else { throw Failure(description: "Unknown action") }
}
do { try main() } catch { fputs("AYM Runtime: \(error)\n", stderr); exit(1) }
