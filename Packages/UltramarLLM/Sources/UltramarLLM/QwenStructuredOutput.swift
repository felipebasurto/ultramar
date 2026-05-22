import Foundation

/// Qwen answer split into visible reply vs optional reasoning blocks.
public struct QwenStructuredOutput: Sendable, Equatable {
    public let answer: String
    public let thinking: String
    public let tokensGenerated: Int

    public init(answer: String, thinking: String, tokensGenerated: Int = 0) {
        self.answer = answer
        self.thinking = thinking
        self.tokensGenerated = tokensGenerated
    }

    public var hasThinking: Bool {
        !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// User-facing text: answer only, or thinking + answer when requested.
    public func formatted(showThinking: Bool) -> String {
        ChatResponseFormatter.format(answer: answer, thinking: thinking, showThinking: showThinking)
    }
}

public struct ChatPresentation: Sendable, Equatable {
    /// When true, include extracted think blocks in the displayed response (Qwen only).
    public var showThinking: Bool
    /// Qwen mode switch. Product defaults to final-only; thinking is debug-only.
    public var qwenReasoningMode: QwenReasoningMode
    /// Optional system prompt override for CLI prompt iteration.
    public var systemPromptOverride: String?

    public init(
        showThinking: Bool = false,
        qwenReasoningMode: QwenReasoningMode = .finalOnly,
        systemPromptOverride: String? = nil
    ) {
        self.showThinking = showThinking
        self.qwenReasoningMode = qwenReasoningMode
        self.systemPromptOverride = systemPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public enum ChatResponseFormatter {
    public static let thinkingHeader = "--- Thinking ---"
    public static let answerHeader = "--- Answer ---"

    public static func format(answer: String, thinking: String, showThinking: Bool) -> String {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedThinking = thinking.trimmingCharacters(in: .whitespacesAndNewlines)

        guard showThinking, !trimmedThinking.isEmpty else {
            return trimmedAnswer
        }
        if trimmedAnswer.isEmpty {
            return "\(thinkingHeader)\n\(trimmedThinking)"
        }
        return "\(thinkingHeader)\n\(trimmedThinking)\n\n\(answerHeader)\n\(trimmedAnswer)"
    }
}
