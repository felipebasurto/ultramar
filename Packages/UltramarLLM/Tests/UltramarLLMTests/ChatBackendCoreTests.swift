import Testing
@testable import UltramarLLM

@Test func modelProfilesDeclareBackendCapabilities() {
    let qwenServer = ModelProfile.qwenServer()
    #expect(qwenServer.id == "qwen-brain")
    #expect(qwenServer.provider == .openAICompatibleLocal)
    #expect(qwenServer.capabilities.text)
    #expect(qwenServer.capabilities.reasoning)
    #expect(qwenServer.capabilities.reasoningControl)
    #expect(!qwenServer.capabilities.vision)

    let gemmaEmbedded = ModelProfile.gemmaEmbedded()
    #expect(gemmaEmbedded.provider == .embeddedLlama)
    #expect(gemmaEmbedded.capabilities.text)
    #expect(gemmaEmbedded.capabilities.vision)
    #expect(!gemmaEmbedded.capabilities.reasoningControl)
}

@Test func chatResponseFormatsHiddenReasoningOnlyWhenRequested() {
    let response = ChatResponse(
        answer: "Respuesta final.",
        hiddenReasoning: "plan interno",
        tokens: 4,
        durationMs: 12,
        backend: .server,
        providerLabel: "qwen"
    )

    #expect(response.displayText(showThinking: false) == "Respuesta final.")
    #expect(response.displayText(showThinking: true).contains(ChatResponseFormatter.thinkingHeader))
    #expect(response.displayText(showThinking: true).contains("plan interno"))
}

@Test func qualityGateIgnoresHiddenReasoningWhenVisibleAnswerIsClean() {
    let response = ChatResponse(
        answer: "Descarga mapas offline, guarda el hotel y prepara efectivo antes de salir.",
        hiddenReasoning: "<think>internal route</think>",
        tokens: 9,
        durationMs: 10,
        backend: .server,
        providerLabel: "qwen"
    )

    let reason = ChatOutputQualityGate.rejectionReason(
        answer: response.answer,
        thinking: response.hiddenReasoning,
        userPrompt: "Consejos para viajar sin datos",
        systemPrompt: TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    )
    #expect(reason == nil)
}
