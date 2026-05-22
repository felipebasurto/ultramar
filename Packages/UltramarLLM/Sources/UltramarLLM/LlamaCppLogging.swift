import Foundation
import LlamaSwift

/// Controls llama.cpp / ggml stderr noise (GGML_LOG_LEVEL env is unreliable across builds).
enum LlamaCppLogging {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var configured = false
    private nonisolated(unsafe) static var suppressAll = true
    private nonisolated(unsafe) static var minimumLevel: ggml_log_level = GGML_LOG_LEVEL_ERROR

    /// Call once before `llama_backend_init()`.
    static func configureFromEnvironment() {
        lock.lock()
        defer { lock.unlock() }
        if configured { return }
        applySettings(Self.parseSettings(ProcessInfo.processInfo.environment["GGML_LOG_LEVEL"]))
        configured = true
    }

    /// Re-apply quiet logging before unload (some llama paths reset or bypass the callback).
    static func ensureQuiet() {
        lock.lock()
        defer { lock.unlock() }
        applySettings((true, GGML_LOG_LEVEL_ERROR))
    }

    private static func applySettings(_ settings: (Bool, ggml_log_level)) {
        suppressAll = settings.0
        minimumLevel = settings.1
        llama_log_set(llamaLogCallback, nil)
    }

    struct Settings: Equatable {
        var suppressAll: Bool
    }

    package static func parseSettingsForTesting(_ raw: String?) -> Settings {
        Settings(suppressAll: parseSettings(raw).0)
    }

    /// `(suppressAll, minimumLevel)` — default is fully quiet unless `GGML_LOG_LEVEL` is set.
    private static func parseSettings(_ raw: String?) -> (Bool, ggml_log_level) {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug":
            return (false, GGML_LOG_LEVEL_DEBUG)
        case "info":
            return (false, GGML_LOG_LEVEL_INFO)
        case "warn", "warning":
            return (false, GGML_LOG_LEVEL_WARN)
        case "error":
            return (false, GGML_LOG_LEVEL_ERROR)
        case "none", "off", "quiet":
            return (true, GGML_LOG_LEVEL_ERROR)
        default:
            return (true, GGML_LOG_LEVEL_ERROR)
        }
    }

    private static let llamaLogCallback: @convention(c) (ggml_log_level, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = {
        level,
        text,
        _ in
        if suppressAll { return }
        guard level.rawValue >= minimumLevel.rawValue else { return }
        guard let text else { return }
        fputs(String(cString: text), stderr)
    }
}
