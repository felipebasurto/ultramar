import Foundation

public enum ChatOutputQualityReason: String, Sendable, Equatable {
    case empty
    case trivial
    case thinkingLeak
    case templateLeak
    case systemPromptEcho
    case userPromptEcho
    case greetingBoilerplate
    case metaPlanningLeak
    case fragment
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
    /// Order:
    ///  1. Protocol leakage (thinking/template tags) – unambiguous failures.
    ///  2. Trivial reply – too short to be useful.
    ///  3. Direct echoes of provided prompts – most specific match wins.
    ///  4. Heuristic meta-planning leaks – generic plan/label narration.
    ///  5. Greeting boilerplate to a non-greeting prompt.
    ///  6. Single-line fragments.
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
        if containsThinkingLeak(trimmed) {
            return .thinkingLeak
        }
        if containsTemplateLeak(trimmed) {
            return .templateLeak
        }
        if isTrivial(trimmed, userPrompt: userPrompt) {
            return .trivial
        }
        if let systemPrompt, echoesSource(trimmed, source: systemPrompt, minimumOverlap: 24) {
            return .systemPromptEcho
        }
        if let userPrompt, QwenThinkingPolicy.echoesUserPrompt(answer: trimmed, userPrompt: userPrompt) {
            return .userPromptEcho
        }
        if containsMetaPlanningLeak(trimmed) {
            return .metaPlanningLeak
        }
        if QwenThinkingPolicy.isGreetingBoilerplateForNonGreeting(answer: trimmed, userPrompt: userPrompt) {
            return .greetingBoilerplate
        }
        if QwenThinkingPolicy.isLikelyFragment(trimmed) {
            return .fragment
        }
        return nil
    }

    /// A non-greeting user prompt should get a substantive answer. We keep the original
    /// "<= 2 useful chars" threshold for greetings (so the short greeting fallback still
    /// passes) and use a stricter ~24-char floor when the user actually asked a question.
    private static func isTrivial(_ text: String, userPrompt: String?) -> Bool {
        let usefulCount = text
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
            .count
        if usefulCount <= 2 {
            return true
        }
        if let userPrompt, !QwenThinkingPolicy.isGreeting(userPrompt) {
            if usefulCount < 24 {
                return true
            }
        }
        return false
    }

    private static func containsThinkingLeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<think")
            || lower.contains("</think")
            || lower.contains("<|redacted_thinking|>")
            || lower.hasPrefix("thinking process")
            || lower.contains("\nthinking process")
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

    /// Catches visible meta-planning labels even when only one line is present
    /// (`isMostlyInstructionEcho` needs 2+ lines).
    private static func containsMetaPlanningLeak(_ text: String) -> Bool {
        if QwenThinkingPolicy.isInstructionEcho(text) { return true }
        if QwenThinkingPolicy.isMostlyInstructionEcho(text) { return true }
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines where QwenThinkingPolicy.isMetaPlanningLine(line) {
            return true
        }
        let lower = text.lowercased()
        let inlineMetaPhrases = [
            "thinking process",
            "analyze the request",
            "for greetings",
            "for travel questions",
            "concise bullet",
            "review constraints",
            "final polish",
            "final check",
            "drafting the response",
            "drafting content",
            "drafting internal",
            "response strategy",
            "user query:",
            "greeting: 2-3",
        ]
        if inlineMetaPhrases.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
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
