import Testing
@testable import UltramarLLM

@Test func qwenSamplingPresetsMatchModelCardValues() {
    let finalOnly = SamplingPreset.qwenFinalOnly
    #expect(finalOnly.temperature == 0.7)
    #expect(finalOnly.topP == 0.8)
    #expect(finalOnly.topK == 20)
    #expect(finalOnly.minP == 0)
    #expect(finalOnly.presencePenalty == 1.5)
    #expect(finalOnly.repeatPenalty == 1.0)

    let thinking = SamplingPreset.qwenThinking
    #expect(thinking.temperature == 1.0)
    #expect(thinking.topP == 0.95)
    #expect(thinking.topK == 20)
    #expect(thinking.minP == 0)
    #expect(thinking.presencePenalty == 1.5)
    #expect(thinking.repeatPenalty == 1.0)
}

@Test func qualityGateRejectsBadLocalOutputs() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "<think>hidden</think>Hola",
            thinking: nil,
            userPrompt: "hola",
            systemPrompt: system
        ) == .thinkingLeak
    )
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "<|im_start|>assistant\nHola",
            thinking: nil,
            userPrompt: "hola",
            systemPrompt: system
        ) == .templateLeak
    )
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "You are Ultramar AI, an offline travel assistant for travelers worldwide.",
            thinking: nil,
            userPrompt: "hola",
            systemPrompt: system
        ) == .systemPromptEcho
    )
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "¿Consejos para viajar a Tailandia sin datos?",
            thinking: nil,
            userPrompt: "¿Consejos para viajar a Tailandia sin datos?",
            systemPrompt: system
        ) == .userPromptEcho
    )
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "ok",
            thinking: nil,
            userPrompt: "hola",
            systemPrompt: system
        ) == .trivial
    )
}

@Test func qualityGateAcceptsUsefulTravelAnswer() {
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: "Descarga mapas offline, guarda la dirección del hotel, lleva algo de efectivo y ten documentos disponibles sin conexión.",
        thinking: nil,
        userPrompt: "¿Consejos para viajar sin datos?",
        systemPrompt: TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    )
    #expect(reason == nil)
}

@Test func qualityGateAllowsHiddenExtractedThinkingWhenAnswerIsClean() {
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: "Hola, soy Ultramar AI. Dime a dónde viajas y te ayudo a preparar lo esencial sin conexión.",
        thinking: "<think>internal plan</think>",
        userPrompt: "Hola",
        systemPrompt: TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    )
    #expect(reason == nil)
}
