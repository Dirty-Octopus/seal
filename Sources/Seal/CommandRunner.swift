import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }

    var combined: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return out + "\n" + err
    }

    var firstLine: String {
        combined.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? ""
    }
}

private final class TimeoutFlag {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum CommandRunner {
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 180
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment {
                    var merged = ProcessInfo.processInfo.environment
                    environment.forEach { merged[$0.key] = $0.value }
                    process.environment = merged
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(
                        status: -1,
                        stdout: "",
                        stderr: "无法启动 \(executable)：\(error.localizedDescription)",
                        timedOut: false
                    ))
                    return
                }

                let timedOut = TimeoutFlag()
                var watchdog: DispatchWorkItem?
                if timeout > 0 {
                    let item = DispatchWorkItem {
                        if process.isRunning {
                            timedOut.set()
                            process.terminate()
                        }
                    }
                    watchdog = item
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: item)
                }

                let group = DispatchGroup()
                var outData = Data()
                var errData = Data()

                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.wait()
                process.waitUntilExit()
                watchdog?.cancel()

                let stdout = String(decoding: outData.prefix(2_000_000), as: UTF8.self)
                let stderr = String(decoding: errData.prefix(2_000_000), as: UTF8.self)
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr,
                    timedOut: timedOut.get()
                ))
            }
        }
    }

    static func commandDisplay(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:=@".contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
