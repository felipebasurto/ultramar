import Foundation

/// Frozen product defaults shared by the iOS app and CLI interactive mode.
public struct ProductChatProfile: Sendable, Equatable {
    public var task: AgentTask
    public var presentation: ChatPresentation
    public var requiresLoadedEngine: Bool
    public var keepEngineLoadedBetweenTurns: Bool
    public var streamingEnabled: Bool

    public init(
        task: AgentTask = .generalChat,
        presentation: ChatPresentation = ChatPresentation(showThinking: false, qwenReasoningMode: .finalOnly),
        requiresLoadedEngine: Bool = true,
        keepEngineLoadedBetweenTurns: Bool = true,
        streamingEnabled: Bool = false
    ) {
        self.task = task
        self.presentation = presentation
        self.requiresLoadedEngine = requiresLoadedEngine
        self.keepEngineLoadedBetweenTurns = keepEngineLoadedBetweenTurns
        self.streamingEnabled = streamingEnabled
    }

    public static let standard = ProductChatProfile()
}
