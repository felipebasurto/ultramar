import Foundation
import os

public struct LogTimer {
    private let logger: Logger
    private let label: String
    private let start: ContinuousClock.Instant

    public init(logger: Logger, label: String) {
        self.logger = logger
        self.label = label
        self.start = ContinuousClock.now
    }

    public func finish(extra: String = "") {
        let durationMs = Self.durationMilliseconds(since: start)
        let suffix = extra.isEmpty ? "" : " \(extra)"
        logger.info("\(self.label, privacy: .public) \(UltramarLog.kv(("duration_ms", durationMs)), privacy: .public)\(suffix, privacy: .public)")
    }

    @discardableResult
    public static func measure<T>(
        logger: Logger,
        label: String,
        extra: @autoclosure () -> String = "",
        _ work: () throws -> T
    ) rethrows -> T {
        let timer = LogTimer(logger: logger, label: label)
        let result = try work()
        timer.finish(extra: extra())
        return result
    }

    @discardableResult
    public static func measure<T>(
        logger: Logger,
        label: String,
        extra: @autoclosure () -> String = "",
        _ work: () async throws -> T
    ) async rethrows -> T {
        let timer = LogTimer(logger: logger, label: label)
        let result = try await work()
        timer.finish(extra: extra())
        return result
    }

    public static func durationMilliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start).components.attoseconds / 1_000_000_000_000_000)
    }
}
