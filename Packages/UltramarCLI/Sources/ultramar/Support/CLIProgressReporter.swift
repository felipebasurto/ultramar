import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Token progress for `ultramar chat --progress` without flooding stderr.
final class CLIProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let enabled: Bool
    private let isTTY: Bool
    private var lastReported = 0
    private var finished = false

    init(enabled: Bool) {
        self.enabled = enabled
        isTTY = isatty(STDERR_FILENO) != 0
    }

    func report(tokens: Int) {
        guard enabled, !finished else { return }
        lock.lock()
        defer { lock.unlock() }

        if isTTY {
            let line = "Generating… tokens=\(tokens)"
            FileHandle.standardError.write(Data("\r\(line)".utf8))
            lastReported = tokens
            return
        }

        guard tokens - lastReported >= 64 || tokens < lastReported else { return }
        FileHandle.standardError.write(Data("tokens=\(tokens)\n".utf8))
        lastReported = tokens
    }

    func finish() {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        if isTTY, lastReported > 0 {
            FileHandle.standardError.write(Data("\n".utf8))
        }
    }
}

enum StderrSilencer {
    static func withSilencedStderr<T>(_ work: () async throws -> T) async rethrows -> T {
        let original = dup(STDERR_FILENO)
        let devNull = open("/dev/null", O_WRONLY)
        if devNull >= 0, original >= 0 {
            dup2(devNull, STDERR_FILENO)
            close(devNull)
        }
        defer {
            if original >= 0 {
                dup2(original, STDERR_FILENO)
                close(original)
            }
        }
        return try await work()
    }
}
