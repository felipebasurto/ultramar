import Foundation
import Testing
import UltramarCore
@testable import UltramarLLM

/// Mock `ChatBackend` that returns a scripted sequence of answers and records every
/// request it received. Lets us exercise `ChatOrchestrator`'s retry/throw paths without
/// reaching into llama.cpp or a live server.
private final class ScriptedBackend: ChatBackend, @unchecked Sendable {
    let kind: ChatBackendKind = .embedded
    let providerLabel: String = "mock"

    private var scripted: [String]
    private(set) var sentRequests: [ChatRequest] = []

    init(answers: [String]) {
        scripted = answers
    }

    func prepare(profile: ModelProfile) async throws {}

    func send(request: ChatRequest) async throws -> ChatResponse {
        sentRequests.append(request)
        let answer = scripted.isEmpty ? "" : scripted.removeFirst()
        return ChatResponse(
            answer: answer,
            hiddenReasoning: nil,
            tokens: 1,
            durationMs: 0,
            backend: kind,
            providerLabel: providerLabel
        )
    }

    func stream(request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func resetSession() {}
    func shutdown() async {}
}

private func makeOrchestrator(answers: [String]) -> (ChatOrchestrator, ScriptedBackend) {
    let backend = ScriptedBackend(answers: answers)
    let orchestrator = ChatOrchestrator(backend: backend, profile: .qwenServer())
    return (orchestrator, backend)
}

private func makeRequest(
    user: String = "¿Consejos para viajar a Tailandia sin datos?",
    systemPrompt: String? = nil,
    reasoningMode: QwenReasoningMode = .finalOnly
) -> ChatRequest {
    ChatRequest(
        messages: [ChatMessage(role: .user, content: user)],
        systemPrompt: systemPrompt,
        reasoningMode: reasoningMode
    )
}

@Test func orchestratorReturnsCleanAnswerWithoutRetry() async throws {
    let cleanAnswer = """
    • Descarga Google Maps offline para Bangkok.
    • Lleva efectivo en bahts; muchos puestos no aceptan tarjeta.
    • Guarda la dirección del hotel y de la embajada.
    • Aprende frases básicas en tailandés.
    """
    let (orchestrator, backend) = makeOrchestrator(answers: [cleanAnswer])
    let response = try await orchestrator.send(makeRequest())
    #expect(response.answer == cleanAnswer)
    #expect(backend.sentRequests.count == 1)
}

@Test func orchestratorInjectsDefaultQwenSystemPromptWhenRequestHasNone() async throws {
    let (orchestrator, backend) = makeOrchestrator(answers: [
        "Pack a power bank, download offline maps for Bangkok, and carry bahts in cash for taxis and markets.",
    ])
    _ = try await orchestrator.send(makeRequest(systemPrompt: nil))
    let sent = try #require(backend.sentRequests.first)
    let canonical = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    #expect(sent.systemPrompt == canonical)
}

@Test func orchestratorPreservesCallerSystemPromptOnFirstAttempt() async throws {
    let customPrompt = "You are a custom travel coach. Answer briefly."
    let (orchestrator, backend) = makeOrchestrator(answers: [
        "Pack a power bank, download offline maps for Bangkok, and carry bahts in cash.",
    ])
    _ = try await orchestrator.send(makeRequest(systemPrompt: customPrompt))
    let sent = try #require(backend.sentRequests.first)
    #expect(sent.systemPrompt == customPrompt)
}

@Test func orchestratorRetriesWithCanonicalPromptWhenFirstAnswerFailsGate() async throws {
    let badAnswer = "¡Hola! Soy Ultramar AI, tu asistente de viaje offline. ¿En qué puedo ayudarte hoy?"
    let goodAnswer = "Lleva efectivo en bahts, descarga mapas offline de Bangkok y guarda la dirección del hotel y de la embajada."
    let customPrompt = "Welcome them politely, then maybe answer."
    let (orchestrator, backend) = makeOrchestrator(answers: [badAnswer, goodAnswer])
    let response = try await orchestrator.send(makeRequest(systemPrompt: customPrompt))
    #expect(response.answer == goodAnswer)
    #expect(backend.sentRequests.count == 2)
    let retry = backend.sentRequests[1]
    #expect(retry.reasoningMode == .finalOnly)
    #expect(retry.showThinking == false)
    #expect(retry.systemPrompt == TravelChatPrompts.systemMessage(for: .qwenFinalOnly))
}

@Test func orchestratorThrowsQualityErrorWhenRetryAlsoFails() async throws {
    let firstBad = "Thinking Process:\n1. Analyze the Request.\n2. Greeting: 2-3 sentences."
    let secondBad = "¡Hola! Soy Ultramar AI. ¿En qué puedo ayudarte?"
    let (orchestrator, _) = makeOrchestrator(answers: [firstBad, secondBad])
    await #expect(throws: ChatOutputQualityError.self) {
        _ = try await orchestrator.send(makeRequest())
    }
}

@Test func orchestratorEscalatesEmptyAnswerToQualityError() async throws {
    let (orchestrator, _) = makeOrchestrator(answers: ["", ""])
    do {
        _ = try await orchestrator.send(makeRequest())
        Issue.record("expected ChatOutputQualityError")
    } catch let error as ChatOutputQualityError {
        if case .rejected(let reason) = error {
            #expect(reason == .empty)
        }
    }
}
