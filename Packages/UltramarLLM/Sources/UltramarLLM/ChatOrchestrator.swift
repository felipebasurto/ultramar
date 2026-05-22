import Foundation
import UltramarCore

public final class ChatOrchestrator: @unchecked Sendable {
    public let backend: any ChatBackend
    public private(set) var profile: ModelProfile

    public init(backend: any ChatBackend, profile: ModelProfile) {
        self.backend = backend
        self.profile = profile
    }

    public static func server(
        baseURL: URL = OpenAICompatibleLocalBackend.defaultBaseURL,
        profile: ModelProfile = .qwenServer()
    ) -> ChatOrchestrator {
        ChatOrchestrator(
            backend: OpenAICompatibleLocalBackend(baseURL: baseURL, profile: profile),
            profile: profile
        )
    }

    public static func embedded(
        profile: ModelProfile = .qwenEmbedded(),
        fileManager: FileManager = .default
    ) -> ChatOrchestrator {
        ChatOrchestrator(
            backend: EmbeddedLlamaBackend(profile: profile, fileManager: fileManager),
            profile: profile
        )
    }

    public func prepare() async throws {
        try await backend.prepare(profile: profile)
    }

    public func prepare(profile: ModelProfile) async throws {
        self.profile = profile
        try await backend.prepare(profile: profile)
    }

    public func send(_ request: ChatRequest) async throws -> ChatResponse {
        let response = try await backend.send(request: request)
        if let reason = rejectionReason(for: response, request: request) {
            UltramarLog.engine.error(
                "quality_gate_rejected \(UltramarLog.kv(("provider", response.providerLabel), ("backend", response.backend.rawValue), ("reason", reason.rawValue), ("tokens_generated", response.tokens), ("answer_chars", response.answer.count)), privacy: .public)"
            )
            var retryRequest = request
            retryRequest.reasoningMode = .finalOnly
            retryRequest.showThinking = false
            let retryResponse = try await backend.send(request: retryRequest)
            if let retryReason = rejectionReason(for: retryResponse, request: retryRequest) {
                UltramarLog.engine.error(
                    "quality_gate_failed_after_retry \(UltramarLog.kv(("provider", retryResponse.providerLabel), ("backend", retryResponse.backend.rawValue), ("reason", retryReason.rawValue), ("tokens_generated", retryResponse.tokens), ("answer_chars", retryResponse.answer.count)), privacy: .public)"
                )
                throw ChatOutputQualityError.rejected(reason: retryReason)
            }
            return retryResponse
        }
        return response
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        backend.stream(request: request)
    }

    public func resetSession() {
        backend.resetSession()
    }

    public func shutdown() async {
        await backend.shutdown()
    }

    private func rejectionReason(
        for response: ChatResponse,
        request: ChatRequest
    ) -> ChatOutputQualityReason? {
        ChatOutputQualityGate.rejectionReason(
            answer: response.answer,
            thinking: response.hiddenReasoning,
            userPrompt: request.lastUserMessage,
            systemPrompt: request.systemPrompt ?? defaultSystemPrompt(for: request)
        )
    }

    private func defaultSystemPrompt(for request: ChatRequest) -> String {
        switch profile.engineRole {
        case .qwenBrain:
            TravelChatPrompts.systemMessage(
                for: TravelChatPrompts.variantForQwen(reasoningMode: request.reasoningMode)
            )
        case .gemmaVision:
            TravelChatPrompts.systemMessage(for: .gemmaChat)
        case .none:
            TravelChatPrompts.systemMessage(for: .foundationModels)
        }
    }
}
