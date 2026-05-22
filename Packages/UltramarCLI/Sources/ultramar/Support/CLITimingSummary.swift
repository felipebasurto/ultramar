import Foundation

/// Inference timing for `ultramar chat` — always printed on stderr after the answer.
struct CLITimingSummary: Sendable, Equatable {
    let engine: String
    let loadDurationMs: Int
    let inferenceDurationMs: Int
    let tokensGenerated: Int

    var totalDurationMs: Int {
        loadDurationMs + inferenceDurationMs
    }

    static func seconds(fromMilliseconds ms: Int) -> String {
        String(format: "%.1f", Double(ms) / 1000.0)
    }

    static func tokensPerSecond(tokens: Int, inferenceMs: Int) -> Double? {
        guard tokens > 0, inferenceMs > 0 else { return nil }
        return Double(tokens) / (Double(inferenceMs) / 1000.0)
    }

    var stderrLine: String {
        var segments: [String] = []
        if loadDurationMs > 0 {
            segments.append("load \(Self.seconds(fromMilliseconds: loadDurationMs))s")
        }

        var generateSegment = "generate \(Self.seconds(fromMilliseconds: inferenceDurationMs))s"
        if tokensGenerated > 0,
           let tokensPerSecond = Self.tokensPerSecond(tokens: tokensGenerated, inferenceMs: inferenceDurationMs)
        {
            generateSegment += " (\(tokensGenerated) tokens, \(String(format: "%.1f", tokensPerSecond)) tok/s)"
        }
        segments.append(generateSegment)
        segments.append("total \(Self.seconds(fromMilliseconds: totalDurationMs))s")
        return "Timing: \(segments.joined(separator: " | "))"
    }

    var jsonFields: [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "load_duration_ms": .int(loadDurationMs),
            "duration_ms": .int(inferenceDurationMs),
            "total_duration_ms": .int(totalDurationMs),
            "tokens_generated": .int(tokensGenerated),
        ]
        if let tokensPerSecond = Self.tokensPerSecond(tokens: tokensGenerated, inferenceMs: inferenceDurationMs) {
            fields["tokens_per_second"] = .double(tokensPerSecond)
        }
        return fields
    }

    static func writeStderrLine(_ summary: CLITimingSummary) {
        FileHandle.standardError.write(Data("\(summary.stderrLine)\n".utf8))
    }
}
