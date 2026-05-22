import Foundation

public enum ChatOutputQualityReason: String, Sendable, Equatable {
    case empty
    case trivial
    case thinkingLeak
    case templateLeak
    case systemPromptEcho
    case userPromptEcho
}

public enum ChatOutputQualityError: Error, LocalizedError, Sendable, Equatable {
    case rejected(reason: ChatOutputQualityReason)

    public var errorDescription: String? {
        switch self {
        case .rejected(let reason):
            "Local model output failed quality checks (\(reason.rawValue)). Try again or adjust the system prompt."
        }
    }
}

public enum ChatOutputQualityGate {
    public static func rejectionReason(
        answer: String,
        thinking: String?,
        userPrompt: String?,
        systemPrompt: String?
    ) -> ChatOutputQualityReason? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        if isTrivial(trimmed) {
            return .trivial
        }
        if containsThinkingLeak(trimmed) {
            return .thinkingLeak
        }
        if containsTemplateLeak(trimmed) {
            return .templateLeak
        }
        if let systemPrompt, echoesSource(trimmed, source: systemPrompt, minimumOverlap: 24) {
            return .systemPromptEcho
        }
        if let userPrompt, QwenThinkingPolicy.echoesUserPrompt(answer: trimmed, userPrompt: userPrompt) {
            return .userPromptEcho
        }
        return nil
    }

    private static func isTrivial(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
        return normalized.count <= 2
    }

    private static func containsThinkingLeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<think")
            || lower.contains("</think")
            || lower.contains("<|redacted_thinking|>")
            || lower.hasPrefix("thinking process")
    }

    private static func containsTemplateLeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "<|im_start|>",
            "<|im_end|>",
            "<|assistant|>",
            "<|user|>",
            "<|system|>",
            "role: system",
            "role: user",
            "role: assistant",
            "system:",
            "assistant:",
            "user:",
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func echoesSource(_ answer: String, source: String, minimumOverlap: Int) -> Bool {
        let answerText = normalize(answer)
        let sourceText = normalize(source)
        guard answerText.count >= minimumOverlap, sourceText.count >= minimumOverlap else { return false }
        if sourceText.contains(answerText), answerText.count >= minimumOverlap {
            return true
        }
        for phrase in sourcePhrases(sourceText, minimumLength: minimumOverlap) where answerText.contains(phrase) {
            return true
        }
        return false
    }

    private static func sourcePhrases(_ source: String, minimumLength: Int) -> [String] {
        let words = source.split(separator: " ").map(String.init)
        guard words.count >= 4 else { return [] }
        var phrases: [String] = []
        for start in words.indices {
            var phrase = ""
            for end in start ..< words.count {
                phrase = phrase.isEmpty ? words[end] : "\(phrase) \(words[end])"
                if phrase.count >= minimumLength {
                    phrases.append(phrase)
                    break
                }
            }
        }
        return phrases
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
