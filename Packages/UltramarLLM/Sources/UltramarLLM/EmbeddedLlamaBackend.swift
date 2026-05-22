import Foundation
import UltramarCore

public final class EmbeddedLlamaBackend: ChatBackend, @unchecked Sendable {
    public let kind: ChatBackendKind = .embedded

    public var providerLabel: String {
        switch profile.engineRole {
        case .qwenBrain:
            "qwen"
        case .gemmaVision:
            "gemma"
        case .none:
            "embedded"
        }
    }

    public let harness: InferenceChatHarness
    private let fileManager: FileManager
    private var profile: ModelProfile

    public init(
        harness: InferenceChatHarness = InferenceChatHarness(),
        profile: ModelProfile = .qwenEmbedded(),
        fileManager: FileManager = .default
    ) {
        self.harness = harness
        self.profile = profile
        self.fileManager = fileManager
    }

    public func prepare(profile: ModelProfile) async throws {
        self.profile = profile
        if let localPath = profile.localPath {
            try await loadExplicitModel(localPath, role: profile.engineRole)
            return
        }

        switch profile.engineRole {
        case .qwenBrain:
            try await harness.loadQwenBrain(fileManager: fileManager)
        case .gemmaVision:
            try await harness.loadGemmaVision(fileManager: fileManager)
        case .none:
            break
        }
    }

    public func send(request: ChatRequest) async throws -> ChatResponse {
        let prompt = request.lastUserMessage ?? ""
        let presentation = ChatPresentation(
            showThinking: request.showThinking,
            qwenReasoningMode: request.reasoningMode,
            systemPromptOverride: request.systemPrompt
        )

        let result: InferenceChatHarness.SendResult
        if profile.engineRole == .qwenBrain {
            var session = session(from: request.messages)
            result = try await harness.sendInSession(
                prompt: prompt,
                session: &session,
                profile: ProductChatProfile(
                    task: request.task,
                    presentation: presentation,
                    requiresLoadedEngine: true,
                    keepEngineLoadedBetweenTurns: true,
                    streamingEnabled: false
                ),
                onTokenProgress: nil,
                onPartialAnswer: nil,
                fileManager: fileManager
            )
        } else {
            result = try await harness.send(
                prompt: prompt,
                task: request.task,
                presentation: presentation,
                fileManager: fileManager
            )
        }

        return ChatResponse(
            answer: result.answer,
            hiddenReasoning: result.thinking,
            tokens: result.tokensGenerated,
            durationMs: result.durationMs,
            backend: .embedded,
            providerLabel: result.providerLabel
        )
    }

    public func stream(request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prompt = request.lastUserMessage ?? ""
                    var session = session(from: request.messages)
                    let presentation = ChatPresentation(
                        showThinking: request.showThinking,
                        qwenReasoningMode: request.reasoningMode,
                        systemPromptOverride: request.systemPrompt
                    )
                    let result = try await harness.sendInSession(
                        prompt: prompt,
                        session: &session,
                        profile: ProductChatProfile(
                            task: request.task,
                            presentation: presentation,
                            requiresLoadedEngine: true,
                            keepEngineLoadedBetweenTurns: true,
                            streamingEnabled: true
                        ),
                        onTokenProgress: { count in
                            continuation.yield(.metrics(ChatMetrics(durationMs: 0, tokens: count)))
                        },
                        onPartialAnswer: { delta in
                            continuation.yield(.token(delta))
                        },
                        fileManager: fileManager
                    )
                    continuation.yield(
                        .final(
                            ChatResponse(
                                answer: result.answer,
                                hiddenReasoning: result.thinking,
                                tokens: result.tokensGenerated,
                                durationMs: result.durationMs,
                                backend: .embedded,
                                providerLabel: result.providerLabel
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func resetSession() {}

    public func shutdown() async {
        await harness.unloadAll()
    }

    private func loadExplicitModel(_ url: URL, role: EngineRole) async throws {
        switch role {
        case .qwenBrain:
            await harness.gemmaEngine.unload()
            try await harness.qwenEngine.load(modelURL: url)
        case .gemmaVision:
            await harness.qwenEngine.unload()
            try await harness.gemmaEngine.load(modelURL: url)
        case .none:
            break
        }
    }

    private func session(from messages: [ChatMessage]) -> ChatSession {
        let turns = messages.dropLastUser().compactMap { message -> ChatTurn? in
            switch message.role {
            case .system:
                return nil
            case .user:
                return ChatTurn(role: .user, content: message.content)
            case .assistant:
                return ChatTurn(role: .assistant, content: message.content)
            }
        }
        return ChatSession(turns: turns)
    }
}

private extension Array where Element == ChatMessage {
    func dropLastUser() -> [ChatMessage] {
        guard last?.role == .user else { return self }
        return Array(dropLast())
    }
}
