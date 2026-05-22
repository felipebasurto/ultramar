import Foundation

public struct ChatTurn: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Equatable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let content: String

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum ChatTokenEstimate {
    static func tokenCount(for text: String) -> Int {
        max(1, (text.count + 2) / 3)
    }

    static func tokens(for turns: [ChatTurn], perTurnOverhead: Int = 4) -> Int {
        turns.reduce(0) { partial, turn in
            partial + tokenCount(for: turn.content) + perTurnOverhead
        }
    }
}
