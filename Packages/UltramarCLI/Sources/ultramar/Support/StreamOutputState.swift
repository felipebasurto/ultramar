import Foundation

/// Thread-safe stdout streaming for `ultramar chat --stream`.
final class StreamOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var wroteVisibleText = false
    private let enabled: Bool
    private let includeSeparator: Bool

    var hasVisibleOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wroteVisibleText
    }

    init(enabled: Bool, includeSeparator: Bool = true) {
        self.enabled = enabled
        self.includeSeparator = includeSeparator
    }

    func write(_ delta: String) {
        guard enabled, !delta.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if !started {
            if includeSeparator {
                FileHandle.standardOutput.write(Data("---\n".utf8))
            }
            started = true
        }
        FileHandle.standardOutput.write(Data(delta.utf8))
        wroteVisibleText = true
    }

    func finish(fallbackAnswer: String) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if !started {
            if includeSeparator {
                FileHandle.standardOutput.write(Data("---\n".utf8))
            }
            started = true
        }
        let trimmed = fallbackAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wroteVisibleText, !trimmed.isEmpty {
            FileHandle.standardOutput.write(Data(trimmed.utf8))
            wroteVisibleText = true
        }
        if wroteVisibleText {
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            FileHandle.standardOutput.write(Data("No response generated.\n".utf8))
        }
    }
}
