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

// MARK: - Smoke-batch regressions

@Test func qualityGateRejectsGreetingBoilerplateForNonGreetingPrompt() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "¡Hola! Soy Ultramar AI, tu asistente de viaje offline. ¿En qué puedo ayudarte hoy?",
            thinking: nil,
            userPrompt: "¿Consejos para viajar a Tailandia sin datos?",
            systemPrompt: system
        ) == .greetingBoilerplate
    )
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "Welcome! I am Ultramar AI, your offline travel companion. What can I help you with?",
            thinking: nil,
            userPrompt: "How do I avoid roaming charges while still navigating a city?",
            systemPrompt: system
        ) == .greetingBoilerplate
    )
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "Bienvenido a Ultramar AI. ¿Adónde viajas hoy?",
            thinking: nil,
            userPrompt: "¿Puedo beber agua del grifo en Bangkok?",
            systemPrompt: system
        ) == .greetingBoilerplate
    )
}

@Test func qualityGateAcceptsShortGreetingReplyToGreetingPrompt() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    #expect(
        ChatOutputQualityGate.rejectionReason(
            answer: "Hola, soy Ultramar AI, tu asistente de viaje offline. ¿A dónde vas o qué necesitas planificar?",
            thinking: nil,
            userPrompt: "hola",
            systemPrompt: system
        ) == nil
    )
}

@Test func qualityGateRejectsThinkingProcessLabelPlainText() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let answer = """
    Thinking Process:
    1. Analyze the Request: The user wants travel tips.
    2. Greeting: 2-3 sentences welcoming the user.
    3. Reply: bullet list of advice.
    """
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: answer,
        thinking: nil,
        userPrompt: "¿Consejos para Tailandia?",
        systemPrompt: system
    )
    #expect(reason == .thinkingLeak)
}

@Test func qualityGateRejectsMetaPlanningBulletsWithoutThinkTags() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let answer = """
    For greetings, welcome the user in 2-3 sentences and ask where they need travel help.
    For travel questions, give practical offline advice in 4-7 concise bullet lines covering maps, connectivity, money, transport, language, culture, or safety.
    """
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: answer,
        thinking: nil,
        userPrompt: "What should I save before a long train trip through Italy?",
        systemPrompt: system
    )
    #expect(reason == .metaPlanningLeak)
}

@Test func qualityGateRejectsResponseStrategyLeak() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let answer = """
    Response Strategy:
    - Language: Spanish.
    - Tone: helpful, travel-focused.
    - Content: bullet list of offline travel advice.
    """
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: answer,
        thinking: nil,
        userPrompt: "Necesito frases básicas en tailandés para taxi, hotel y comida.",
        systemPrompt: system
    )
    #expect(reason == .metaPlanningLeak)
}

@Test func qualityGateRejectsSingleLineConciseBulletLeak() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: "I will give 4-7 concise bullet lines about maps, connectivity, money and transport.",
        thinking: nil,
        userPrompt: "Give me a compact offline packing checklist for Japan in winter.",
        systemPrompt: system
    )
    #expect(reason == .metaPlanningLeak)
}

@Test func qualityGateRejectsLabelOnlyFragment() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: "Cuando viajes a un país sin datos móviles, recuerda lo siguiente:",
        thinking: nil,
        userPrompt: "What should I save before a long train trip through Italy?",
        systemPrompt: system
    )
    #expect(reason == .fragment)
}

@Test func qualityGateRejectsShortTrivialAnswerToTravelQuestion() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: "Sí, claro.",
        thinking: nil,
        userPrompt: "How should I plan cash and cards for a country where cards may fail?",
        systemPrompt: system
    )
    #expect(reason == .trivial)
}

@Test func qualityGateAcceptsHealthAnswerThatAdvisesConsultingAProfessional() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let answer = """
    Si te sientes mal durante el viaje, descansa, bebe agua e identifica los \
    síntomas. Localiza la farmacia o clínica más cercana usando mapas \
    descargados antes y, si los síntomas persisten o empeoran, consulta a un \
    profesional sanitario cualificado o llama a tu seguro de viaje.
    """
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: answer,
        thinking: nil,
        userPrompt: "¿Qué hago si me siento mal durante un viaje? Responde con cautela.",
        systemPrompt: system
    )
    #expect(reason == nil)
}

@Test func qualityGateAcceptsThailandSinDatosAdviceWithoutGreetingBoilerplate() {
    let system = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    let answer = """
    • Descarga Google Maps offline para Bangkok, Chiang Mai y las zonas que vayas a visitar.
    • Lleva efectivo en bahts; muchos puestos y taxis no aceptan tarjeta.
    • Guarda la dirección del hotel y de la embajada por escrito y en el teléfono.
    • Aprende frases básicas en tailandés para taxi, hotel y comida.
    • Instala Grab y Google Translate y descarga el paquete de tailandés.
    """
    let reason = ChatOutputQualityGate.rejectionReason(
        answer: answer,
        thinking: nil,
        userPrompt: "¿Consejos para viajar a Tailandia sin datos?",
        systemPrompt: system
    )
    #expect(reason == nil)
}
