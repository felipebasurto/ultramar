import Foundation
import UltramarCore

public enum OpenAICompatibleLocalBackendError: Error, LocalizedError, Sendable, Equatable {
    case invalidBaseURL(String)
    case invalidHTTPResponse
    case badStatus(Int, String)
    case missingChoice
    case invalidStreamPayload(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            "Invalid OpenAI-compatible base URL: \(value)"
        case .invalidHTTPResponse:
            "Local inference server returned a non-HTTP response."
        case .badStatus(let status, let body):
            "Local inference server returned HTTP \(status): \(body)"
        case .missingChoice:
            "Local inference server response did not include a chat completion choice."
        case .invalidStreamPayload(let line):
            "Local inference server returned an invalid stream event: \(line)"
        }
    }
}

public final class OpenAICompatibleLocalBackend: ChatBackend, @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8080/v1")!

    public let kind: ChatBackendKind = .server
    public let providerLabel: String

    private let baseURL: URL
    private let session: URLSession
    private var profile: ModelProfile

    public init(
        baseURL: URL = OpenAICompatibleLocalBackend.defaultBaseURL,
        session: URLSession = .shared,
        profile: ModelProfile = .qwenServer()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.profile = profile
        self.providerLabel = profile.engineRole == .gemmaVision ? "gemma-server" : "qwen-server"
    }

    public func prepare(profile: ModelProfile) async throws {
        self.profile = profile
    }

    public func send(request: ChatRequest) async throws -> ChatResponse {
        let httpRequest = try urlRequest(for: request, stream: false)
        let start = ContinuousClock.now
        let (data, response) = try await session.data(for: httpRequest)
        try Self.validate(response: response, data: data)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = completion.choices.first else {
            throw OpenAICompatibleLocalBackendError.missingChoice
        }
        let split = splitReasoning(from: choice.message.content, userPrompt: request.lastUserMessage)
        let durationMs = LogTimer.durationMilliseconds(since: start)
        return ChatResponse(
            answer: split.answer,
            hiddenReasoning: split.thinking,
            tokens: completion.usage?.completionTokens ?? 0,
            durationMs: durationMs,
            backend: .server,
            providerLabel: providerLabel
        )
    }

    public func stream(request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let httpRequest = try urlRequest(for: request, stream: true)
                    let start = ContinuousClock.now
                    let (bytes, urlResponse) = try await session.bytes(for: httpRequest)
                    try Self.validate(response: urlResponse, data: Data())

                    var raw = ""
                    var filter = QwenThinkingPolicy.GenerationFilter(userPrompt: request.lastUserMessage)
                    var tokens = 0
                    for try await line in bytes.lines {
                        let events = try Self.parseServerSentEvents(line)
                        for event in events {
                            switch event {
                            case .token(let token):
                                raw += token
                                tokens += 1
                                let visibleDelta = filter.append(token)
                                if !visibleDelta.isEmpty {
                                    continuation.yield(.token(visibleDelta))
                                }
                            default:
                                continuation.yield(event)
                            }
                        }
                    }

                    let finalized = QwenThinkingPolicy.finalizeGeneration(
                        raw: raw,
                        visibleText: filter.visibleText,
                        thinkingText: filter.thinkingText,
                        userPrompt: request.lastUserMessage
                    )
                    let finalResponse = ChatResponse(
                        answer: finalized.answer,
                        hiddenReasoning: finalized.thinking,
                        tokens: tokens,
                        durationMs: LogTimer.durationMilliseconds(since: start),
                        backend: .server,
                        providerLabel: providerLabel
                    )
                    continuation.yield(.final(finalResponse))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func resetSession() {}

    public func shutdown() async {}

    func encodedRequestBody(for request: ChatRequest, stream: Bool) throws -> Data {
        let outbound = OpenAIChatCompletionRequest(
            model: profile.modelName,
            messages: outboundMessages(for: request),
            temperature: request.sampling.temperature,
            topP: request.sampling.topP,
            topK: request.sampling.topK,
            minP: request.sampling.minP,
            presencePenalty: request.sampling.presencePenalty,
            frequencyPenalty: request.sampling.frequencyPenalty,
            repeatPenalty: request.sampling.repeatPenalty,
            maxTokens: request.maxTokens,
            stream: stream
        )
        return try JSONEncoder().encode(outbound)
    }

    static func parseServerSentEvents(_ text: String) throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]" else { continue }
            guard let data = payload.data(using: .utf8) else {
                throw OpenAICompatibleLocalBackendError.invalidStreamPayload(payload)
            }
            let chunk = try JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data)
            for choice in chunk.choices {
                if let token = choice.delta.content, !token.isEmpty {
                    events.append(.token(token))
                }
            }
        }
        return events
    }

    private func urlRequest(for request: ChatRequest, stream: Bool) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encodedRequestBody(for: request, stream: stream)
        return httpRequest
    }

    private func outboundMessages(for request: ChatRequest) -> [OpenAIChatMessage] {
        var messages: [OpenAIChatMessage] = []
        if let systemPrompt = request.systemPrompt {
            messages.append(OpenAIChatMessage(role: .system, content: systemPrompt))
        }

        let lastUserIndex = request.messages.lastIndex(where: { $0.role == .user })
        for (index, message) in request.messages.enumerated() {
            var content = message.content
            if index == lastUserIndex, profile.capabilities.reasoningControl {
                content = QwenThinkingPolicy.userMessageForInference(
                    content,
                    reasoningMode: request.reasoningMode
                )
            }
            messages.append(OpenAIChatMessage(role: message.role, content: content))
        }
        return messages
    }

    private func splitReasoning(from raw: String, userPrompt: String?) -> (answer: String, thinking: String?) {
        let thinking = QwenThinkingPolicy.extractThinkingContent(from: raw)
        let visible = QwenThinkingPolicy.visibleAnswer(from: raw)
        let finalized = QwenThinkingPolicy.finalizeGeneration(
            raw: raw,
            visibleText: visible,
            thinkingText: thinking,
            userPrompt: userPrompt
        )
        return (finalized.answer, finalized.thinking.nilIfEmpty)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleLocalBackendError.invalidHTTPResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAICompatibleLocalBackendError.badStatus(http.statusCode, body)
        }
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Float
    let topP: Float
    let topK: Int32
    let minP: Float
    let presencePenalty: Float
    let frequencyPenalty: Float
    let repeatPenalty: Float
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case minP = "min_p"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case repeatPenalty = "repeat_penalty"
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct OpenAIChatMessage: Codable {
    let role: ChatMessage.Role
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String
        }

        let message: Message
    }

    struct Usage: Decodable {
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case completionTokens = "completion_tokens"
        }
    }

    let choices: [Choice]
    let usage: Usage?
}

private struct ChatCompletionStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
