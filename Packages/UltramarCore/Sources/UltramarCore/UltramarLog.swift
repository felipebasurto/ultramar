import Foundation
import os

public enum UltramarLog {
    private static let subsystem = AppInfo.bundleIdentifier

    public static let models = Logger(subsystem: subsystem, category: "models")
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let routing = Logger(subsystem: subsystem, category: "routing")
    public static let rag = Logger(subsystem: subsystem, category: "rag")
    public static let fm = Logger(subsystem: subsystem, category: "fm")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let perf = Logger(subsystem: subsystem, category: "perf")

    public static func kv(_ pairs: (String, CustomStringConvertible)...) -> String {
        kv(pairs)
    }

    public static func kv(_ pairs: [(String, CustomStringConvertible)]) -> String {
        pairs.map { "\($0.0)=\($0.1.description)" }.joined(separator: " ")
    }

    public static func bytesLabel(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    public static func shaPrefix(_ digest: String) -> String {
        String(digest.prefix(12))
    }

    /// Collapses whitespace for one-line diagnostic fields. Do not use for prompts, KB, answers, or thinking.
    public static func singleLine(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
