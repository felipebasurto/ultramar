import Testing
@testable import UltramarLLM

private let thinkOpen = "\u{3C}think\u{3E}"
private let thinkClose = "\u{3C}/think\u{3E}"
private let redactedThinkOpen = "\u{3C}|redacted_thinking|\u{3E}"

@Test func qwenFinalOnlyAppendsNoThinkByDefault() {
    #expect(QwenThinkingPolicy.userMessageForInference("Add", reasoningMode: .finalOnly) == "Add /no_think")
}

@Test func qwenThinkingPolicyAppendsNoThinkWhenSuppressed() {
    #expect(QwenThinkingPolicy.userMessageForInference("Add", reasoningMode: .finalOnly) == "Add /no_think")
}

@Test func qwenThinkingPolicyAppendsThinkForDebugMode() {
    #expect(QwenThinkingPolicy.userMessageForInference("Add", reasoningMode: .thinking) == "Add /think")
}

@Test func finalizeGenerationRejectsHolaInstructionEcho() {
    let echo = """
    • at least five distinct practical tips in a short paragraph or 5–7 bullet lines (maps, connectivity, money, transport, language, culture, safety).
    • Never reply with only one or two sentences unless explicitly asked for brevity.
    • Do not diagnose medical conditions.
    • Determine the Response Strategy:
    • Language: Spanish.
    • Tone: Helpful, professional, travel-focused.
    • Content: Since the user just said "hello", I need to introduce myself and offer practical travel tips relevant to general offline travel (since I'm an offline assistant).
    """
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: echo,
        visibleText: echo,
        thinkingText: "",
        userPrompt: "hola"
    )
    #expect(result.answer.contains("Ultramar AI"))
    #expect(!result.answer.contains("Response Strategy"))
}

@Test func greetingFallbackAnswerForSpanishHello() {
    let reply = QwenThinkingPolicy.greetingFallbackAnswer(for: "hola")
    #expect(reply != nil)
    #expect(reply!.localizedCaseInsensitiveContains("Ultramar AI"))
}

@Test func isMostlyInstructionEchoDetectsPlanningBullets() {
    let text = """
    • at least five distinct practical tips in a short paragraph.
    • Never reply with only one or two sentences unless explicitly asked for brevity.
    • Determine the Response Strategy:
    """
    #expect(QwenThinkingPolicy.isMostlyInstructionEcho(text))
}

@Test func finalizeGenerationRejectsInstructionEchoAnswer() {
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: "Reply in the same language the user used.",
        visibleText: "Reply in the same language the user used.",
        thinkingText: ""
    )
    #expect(result.answer == QwenThinkingPolicy.generationFailedMessage)
}

@Test func sanitizeFinalAnswerRejectsPromptFragment() {
    #expect(QwenThinkingPolicy.sanitizeFinalAnswer("Reply in the same language the user used.").isEmpty)
    #expect(!QwenThinkingPolicy.sanitizeFinalAnswer("Descarga mapas offline antes de volar.").isEmpty)
}

@Test func sanitizeFinalAnswerRejectsUserPromptEcho() {
    let prompt = "¿Consejos para viajar a Tailandia sin datos?"
    #expect(
        QwenThinkingPolicy.sanitizeFinalAnswer(prompt, userPrompt: prompt).isEmpty
    )
    #expect(
        QwenThinkingPolicy.echoesUserPrompt(
            answer: "Consejos para viajar a Tailandia sin datos",
            userPrompt: prompt
        )
    )
    #expect(
        !QwenThinkingPolicy.sanitizeFinalAnswer(
            "Lleva mapas offline, efectivo y una tarjeta con frases en tailandés.",
            userPrompt: prompt
        ).isEmpty
    )
}

@Test func qwenThinkingPolicyDoesNotDuplicateNoThinkSuffix() {
    #expect(QwenThinkingPolicy.userMessageForInference("Add /no_think", reasoningMode: .finalOnly) == "Add /no_think")
}

@Test func qwenThinkingPolicyStripsCompleteThinkBlock() {
    let raw = "\(thinkOpen)Thinking Process:\n1. Analyze\(thinkClose)What would you like to add?"
    #expect(QwenThinkingPolicy.sanitizeOutput(raw) == "What would you like to add?")
}

@Test func qwenThinkingPolicyExtractsThinkBlock() {
    let raw = "\(thinkOpen)Reasoning here\(thinkClose)Visible answer."
    #expect(QwenThinkingPolicy.extractThinkingContent(from: raw) == "Reasoning here")
}

@Test func qwenThinkingPolicyStripsRedactedThinkBlock() {
    let raw = "\(redactedThinkOpen)internal reasoning\(thinkClose)Visible answer."
    #expect(QwenThinkingPolicy.sanitizeOutput(raw) == "Visible answer.")
}

@Test func qwenThinkingPolicyDiscardsTruncatedThinkBlockFromVisibleAnswer() {
    let raw = "\(thinkOpen)Thinking Process:\n1. Analyze the Request:\n   * User Input: \"Add\""
    #expect(QwenThinkingPolicy.sanitizeOutput(raw).isEmpty)
    #expect(!QwenThinkingPolicy.extractThinkingContent(from: raw).isEmpty)
}

@Test func qwenThinkingPolicyLeavesPlainTextUnchanged() {
    let raw = "Pack light layers for Bangkok in March."
    #expect(QwenThinkingPolicy.sanitizeOutput(raw) == raw)
}

@Test func qwenGenerationFilterStreamsVisibleTextAfterThinkBlock() {
    var filter = QwenThinkingPolicy.GenerationFilter()
    #expect(filter.append("\(thinkOpen)reason") == "")
    #expect(filter.thinkingText.contains("reason") || filter.thinkingText == "reason")
    #expect(filter.append("ing\(thinkClose)Hello") == "Hello")
    #expect(filter.visibleText == "Hello")
    #expect(filter.append(" world") == " world")
    #expect(filter.visibleText == "Hello world")
}

@Test func qwenGenerationFilterStreamsPlainTextImmediately() {
    var filter = QwenThinkingPolicy.GenerationFilter()
    #expect(filter.append("Hi") == "Hi")
    #expect(filter.append(" there") == " there")
    #expect(filter.visibleText == "Hi there")
}

@Test func qwenGenerationFilterDoesNotStreamUserPromptEcho() {
    let prompt = "¿Consejos para viajar a Tailandia sin datos?"
    var filter = QwenThinkingPolicy.GenerationFilter(userPrompt: prompt)
    #expect(filter.append("¿Consejos para") == "")
    #expect(filter.append(" viajar a Tailandia sin datos?") == "")
    #expect(filter.visibleText == prompt)
}

@Test func qwenGenerationFilterHoldsBackTruncatedThinkBlockFromVisible() {
    var filter = QwenThinkingPolicy.GenerationFilter()
    #expect(filter.append("\(thinkOpen)still thinking") == "")
    #expect(filter.visibleText.isEmpty)
    #expect(!filter.thinkingText.isEmpty)
}

@Test func visibleAnswerRecoversTextAfterClosedThinkBlock() {
    let raw = "\(thinkOpen)reasoning\(thinkClose)Hello from Bangkok."
    #expect(QwenThinkingPolicy.visibleAnswer(from: raw) == "Hello from Bangkok.")
}

@Test func chatResponseFormatterHidesThinkingByDefault() {
    let formatted = ChatResponseFormatter.format(
        answer: "Hi",
        thinking: "internal",
        showThinking: false
    )
    #expect(formatted == "Hi")
}

@Test func extractPlannedReplyFromThinkingRecoversSpanishBullets() {
    let thinking = """
    5. **Review Constraints:**
    *Reply:*
        * Descargar mapas offline en Google Maps antes de salir.
        * Guardar números de emergencia y de la embajada en el teléfono.
        * Llevar efectivo en bahts; muchos puestos no aceptan tarjeta.
        * Descargar Grab y Google Translate en modo offline.
        * Aprende saludos básicos en tailandés para mercados y templos.
    *Final Check:*
    """
    let reply = QwenThinkingPolicy.extractPlannedReplyFromThinking(
        thinking,
        userPrompt: "¿Consejos para viajar a Tailandia sin datos?"
    )
    #expect(reply != nil)
    #expect(reply!.contains("mapas offline"))
    #expect(reply!.contains("•"))
}

@Test func finalizeGenerationDoesNotRecoverUserQueryFromThinking() {
    let prompt = "¿Consejos para viajar a Tailandia sin datos?"
    let thinking = """
    Thinking Process:
    **User Query:** "\(prompt)" (Tips for traveling to Thailand without data?)
    *   Constraints: 2-3
    """
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: thinking,
        visibleText: "",
        thinkingText: thinking,
        userPrompt: prompt
    )
    #expect(result.answer == QwenThinkingPolicy.generationFailedMessage)
}

@Test func finalizeGenerationRecoversQuotedDraftWhenVisibleEmpty() {
    let thinking = """
    6. **Final Polish:**
       "Hello! I'm Ultramar AI, here to help you navigate travel plans without an internet connection. Where would you like to go?" (2 sentences)
    """
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: "\(thinkOpen)\(thinking)",
        visibleText: "",
        thinkingText: thinking
    )
    #expect(result.answer.contains("Ultramar AI"))
    #expect(result.thinking == thinking.trimmingCharacters(in: .whitespacesAndNewlines))
}

@Test func chatResponseFormatterShowsThinkingWhenAsked() {
    let formatted = ChatResponseFormatter.format(
        answer: "Hi",
        thinking: "internal",
        showThinking: true
    )
    #expect(formatted.contains(ChatResponseFormatter.thinkingHeader))
    #expect(formatted.contains("internal"))
    #expect(formatted.contains("Hi"))
}
