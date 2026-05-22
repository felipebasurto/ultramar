import Foundation
import UltramarCore

public enum ChatBackendKind: String, Sendable, Equatable {
    case server
    case embedded
    case appleFoundationModels
}

public enum ChatBackendProvider: String, Sendable, Equatable {
    case openAICompatibleLocal
    case embeddedLlama
    case appleFoundationModels
}

public struct ModelCapabilities: Sendable, Equatable {
    public let text: Bool
    public let vision: Bool
    public let reasoning: Bool
    public let reasoningControl: Bool
    public let toolUse: Bool

    public init(
        text: Bool = true,
        vision: Bool = false,
        reasoning: Bool = false,
        reasoningControl: Bool = false,
        toolUse: Bool = false
    ) {
        self.text = text
        self.vision = vision
        self.reasoning = reasoning
        self.reasoningControl = reasoningControl
        self.toolUse = toolUse
    }
}

public struct ModelProfile: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let engineRole: EngineRole
    public let provider: ChatBackendProvider
    public let backend: ChatBackendKind
    public let modelName: String
    public let localPath: URL?
    public let capabilities: ModelCapabilities
    public let defaultSampling: SamplingParameters

    public init(
        id: String,
        displayName: String,
        engineRole: EngineRole,
        provider: ChatBackendProvider,
        backend: ChatBackendKind,
        modelName: String,
        localPath: URL? = nil,
        capabilities: ModelCapabilities,
        defaultSampling: SamplingParameters
    ) {
        self.id = id
        self.displayName = displayName
        self.engineRole = engineRole
        self.provider = provider
        self.backend = backend
        self.modelName = modelName
        self.localPath = localPath
        self.capabilities = capabilities
        self.defaultSampling = defaultSampling
    }

    public static func qwenServer(modelName: String = "qwen") -> ModelProfile {
        ModelProfile(
            id: ModelCatalog.qwenBrain.id,
            displayName: ModelCatalog.qwenBrain.displayName,
            engineRole: .qwenBrain,
            provider: .openAICompatibleLocal,
            backend: .server,
            modelName: modelName,
            capabilities: ModelCapabilities(
                text: true,
                reasoning: true,
                reasoningControl: true,
                toolUse: true
            ),
            defaultSampling: SamplingPreset.qwenFinalOnly
        )
    }

    public static func gemmaServer(modelName: String = "gemma") -> ModelProfile {
        ModelProfile(
            id: ModelCatalog.gemmaVision.id,
            displayName: ModelCatalog.gemmaVision.displayName,
            engineRole: .gemmaVision,
            provider: .openAICompatibleLocal,
            backend: .server,
            modelName: modelName,
            capabilities: ModelCapabilities(text: true, vision: true),
            defaultSampling: SamplingPreset.qwenFinalOnly
        )
    }

    public static func qwenEmbedded(localPath: URL? = nil) -> ModelProfile {
        ModelProfile(
            id: ModelCatalog.qwenBrain.id,
            displayName: ModelCatalog.qwenBrain.displayName,
            engineRole: .qwenBrain,
            provider: .embeddedLlama,
            backend: .embedded,
            modelName: ModelCatalog.qwenBrain.filename,
            localPath: localPath,
            capabilities: ModelCapabilities(
                text: true,
                reasoning: true,
                reasoningControl: true,
                toolUse: true
            ),
            defaultSampling: SamplingPreset.qwenFinalOnly
        )
    }

    public static func gemmaEmbedded(localPath: URL? = nil) -> ModelProfile {
        ModelProfile(
            id: ModelCatalog.gemmaVision.id,
            displayName: ModelCatalog.gemmaVision.displayName,
            engineRole: .gemmaVision,
            provider: .embeddedLlama,
            backend: .embedded,
            modelName: ModelCatalog.gemmaVision.filename,
            localPath: localPath,
            capabilities: ModelCapabilities(text: true, vision: true),
            defaultSampling: SamplingPreset.qwenFinalOnly
        )
    }

    public static func appleFoundationModels() -> ModelProfile {
        ModelProfile(
            id: "apple-foundation-models",
            displayName: "Apple Foundation Models",
            engineRole: .none,
            provider: .appleFoundationModels,
            backend: .appleFoundationModels,
            modelName: "apple-foundation-models",
            capabilities: ModelCapabilities(text: true),
            defaultSampling: SamplingPreset.qwenFinalOnly
        )
    }
}

public struct ChatMessage: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Equatable, Codable {
        case system
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

    public init(turn: ChatTurn) {
        self.init(
            role: turn.role == .user ? .user : .assistant,
            content: turn.content
        )
    }
}

public struct ChatRequest: Sendable, Equatable {
    public var messages: [ChatMessage]
    public var systemPrompt: String?
    public var sampling: SamplingParameters
    public var reasoningMode: QwenReasoningMode
    public var maxTokens: Int
    public var sessionId: String?
    public var showThinking: Bool
    public var task: AgentTask

    public init(
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        sampling: SamplingParameters = SamplingPreset.qwenFinalOnly,
        reasoningMode: QwenReasoningMode = .finalOnly,
        maxTokens: Int = 512,
        sessionId: String? = nil,
        showThinking: Bool = false,
        task: AgentTask = .generalChat
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sampling = sampling
        self.reasoningMode = reasoningMode
        self.maxTokens = maxTokens
        self.sessionId = sessionId
        self.showThinking = showThinking
        self.task = task
    }

    public var lastUserMessage: String? {
        messages.last(where: { $0.role == .user })?.content
    }
}

public struct ChatResponse: Sendable, Equatable {
    public let answer: String
    public let hiddenReasoning: String?
    public let tokens: Int
    public let durationMs: Int
    public let backend: ChatBackendKind
    public let providerLabel: String

    public init(
        answer: String,
        hiddenReasoning: String? = nil,
        tokens: Int = 0,
        durationMs: Int = 0,
        backend: ChatBackendKind,
        providerLabel: String
    ) {
        self.answer = answer
        self.hiddenReasoning = hiddenReasoning?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.tokens = tokens
        self.durationMs = durationMs
        self.backend = backend
        self.providerLabel = providerLabel
    }

    public func displayText(showThinking: Bool) -> String {
        ChatResponseFormatter.format(
            answer: answer,
            thinking: hiddenReasoning ?? "",
            showThinking: showThinking
        )
    }
}

public struct ChatMetrics: Sendable, Equatable {
    public let durationMs: Int
    public let tokens: Int

    public init(durationMs: Int, tokens: Int) {
        self.durationMs = durationMs
        self.tokens = tokens
    }
}

public enum ChatEvent: Sendable, Equatable {
    case status(String)
    case token(String)
    case reasoning(String)
    case final(ChatResponse)
    case metrics(ChatMetrics)
    case error(String)
}

public protocol ChatBackend: Sendable {
    var kind: ChatBackendKind { get }
    var providerLabel: String { get }

    func prepare(profile: ModelProfile) async throws
    func send(request: ChatRequest) async throws -> ChatResponse
    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error>
    func resetSession()
    func shutdown() async
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
