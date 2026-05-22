import Foundation

public struct ChatSession: Sendable, Equatable {
    public private(set) var turns: [ChatTurn]

    public init(turns: [ChatTurn] = []) {
        self.turns = turns
    }

    public var isEmpty: Bool {
        turns.isEmpty
    }

    public mutating func appendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        turns.append(ChatTurn(role: .user, content: trimmed))
    }

    public mutating func appendAssistantMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        turns.append(ChatTurn(role: .assistant, content: trimmed))
    }

    public mutating func clear() {
        turns.removeAll()
    }

    public mutating func removeLastTurnIfUser() {
        guard turns.last?.role == .user else { return }
        turns.removeLast()
    }

    /// Returns a prefix of `turns` that fits within the prompt token budget.
    public func windowedTurns(
        contextTokens: Int = 4096,
        systemReserve: Int = 512,
        generationReserve: Int
    ) -> [ChatTurn] {
        guard !turns.isEmpty else { return [] }

        let budget = max(256, contextTokens - systemReserve - generationReserve)
        var window = turns

        while ChatTokenEstimate.tokens(for: window) > budget, window.count > 1 {
            window.removeFirst()
            while let first = window.first, first.role == .assistant, window.count > 1 {
                window.removeFirst()
            }
        }

        return window
    }
}
