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

// MARK: - Greeting boilerplate detection

@Test func isGreetingDetectsHolaAndHello() {
    #expect(QwenThinkingPolicy.isGreeting("hola"))
    #expect(QwenThinkingPolicy.isGreeting("Hola"))
    #expect(QwenThinkingPolicy.isGreeting("hello"))
    #expect(QwenThinkingPolicy.isGreeting("Buenas"))
    #expect(!QwenThinkingPolicy.isGreeting("¿Consejos para Tailandia?"))
}

@Test func isGreetingOnlyResponseFlagsShortHolaWithQuestion() {
    #expect(
        QwenThinkingPolicy.isGreetingOnlyResponse(
            "¡Hola! Soy Ultramar AI, tu asistente de viaje offline. ¿En qué te puedo ayudar?"
        )
    )
    #expect(
        QwenThinkingPolicy.isGreetingOnlyResponse(
            "Welcome! I am Ultramar AI. How can I help you today?"
        )
    )
    #expect(
        QwenThinkingPolicy.isGreetingOnlyResponse(
            "Bienvenido a Ultramar AI."
        )
    )
}

@Test func isGreetingOnlyResponseAcceptsRealAdviceEvenIfItOpensWithHola() {
    let advice = """
    • Descarga mapas offline para Bangkok.
    • Lleva efectivo en bahts.
    • Aprende frases básicas en tailandés.
    • Guarda los teléfonos de la embajada.
    """
    #expect(!QwenThinkingPolicy.isGreetingOnlyResponse(advice))

    let bulletedHola = "Hola, aquí van algunos consejos:\n• Descarga mapas offline para Bangkok.\n• Lleva efectivo en bahts."
    #expect(!QwenThinkingPolicy.isGreetingOnlyResponse(bulletedHola))
}

@Test func isGreetingBoilerplateForNonGreetingShortCircuitsForGreetingPrompt() {
    let greetingReply = "Hola, soy Ultramar AI. ¿A dónde vas?"
    #expect(
        !QwenThinkingPolicy.isGreetingBoilerplateForNonGreeting(
            answer: greetingReply,
            userPrompt: "hola"
        )
    )
    #expect(
        QwenThinkingPolicy.isGreetingBoilerplateForNonGreeting(
            answer: greetingReply,
            userPrompt: "¿Consejos para viajar a Tailandia sin datos?"
        )
    )
}

@Test func sanitizeFinalAnswerRejectsGreetingBoilerplateForNonGreeting() {
    let greetingReply = "¡Hola! Soy Ultramar AI. ¿En qué puedo ayudarte hoy?"
    #expect(
        QwenThinkingPolicy.sanitizeFinalAnswer(
            greetingReply,
            userPrompt: "¿Consejos para viajar a Tailandia sin datos?"
        ).isEmpty
    )
    #expect(
        !QwenThinkingPolicy.sanitizeFinalAnswer(
            greetingReply,
            userPrompt: "hola"
        ).isEmpty
    )
}

// MARK: - Fragment detection

@Test func isLikelyFragmentFlagsLabelOnlyLine() {
    #expect(
        QwenThinkingPolicy.isLikelyFragment(
            "Cuando viajes a un país sin datos móviles, recuerda lo siguiente:"
        )
    )
}

@Test func isLikelyFragmentFlagsShortIncompleteSentence() {
    #expect(QwenThinkingPolicy.isLikelyFragment("Mapas y efectivo,"))
    #expect(QwenThinkingPolicy.isLikelyFragment("Lleva"))
}

@Test func isLikelyFragmentFlagsLinesThatAreAllLabels() {
    let labels = """
    Maps:
    Cash:
    Documents:
    """
    #expect(QwenThinkingPolicy.isLikelyFragment(labels))
}

@Test func isLikelyFragmentAcceptsFullParagraph() {
    let answer = "Pack a power bank, download offline maps for Tokyo and Kyoto before leaving Wi-Fi, and carry yen for small shops."
    #expect(!QwenThinkingPolicy.isLikelyFragment(answer))
}

@Test func isLikelyFragmentAcceptsMultiBulletList() {
    let answer = """
    • Descarga mapas offline.
    • Lleva efectivo en bahts.
    • Aprende frases en tailandés.
    """
    #expect(!QwenThinkingPolicy.isLikelyFragment(answer))
}

@Test func sanitizeFinalAnswerRejectsFragmentEndingInColon() {
    let fragment = "Cuando viajes a un país sin datos móviles, recuerda lo siguiente:"
    #expect(QwenThinkingPolicy.sanitizeFinalAnswer(fragment).isEmpty)
}

// MARK: - Meta planning leaks

@Test func isMetaPlanningLineDetectsExpandedPrefixes() {
    #expect(QwenThinkingPolicy.isMetaPlanningLine("Greeting: 2-3 sentences welcoming"))
    #expect(QwenThinkingPolicy.isMetaPlanningLine("Reply: bullet list of travel tips"))
    #expect(QwenThinkingPolicy.isMetaPlanningLine("Approach: respond with offline guidance"))
    #expect(QwenThinkingPolicy.isMetaPlanningLine("- For greetings, welcome the user"))
    #expect(QwenThinkingPolicy.isMetaPlanningLine("• For travel questions, give offline advice"))
    #expect(QwenThinkingPolicy.isMetaPlanningLine("Step 1: identify the request"))
    #expect(QwenThinkingPolicy.isMetaPlanningLine("Final Polish: tighten wording"))
    #expect(!QwenThinkingPolicy.isMetaPlanningLine("Descarga mapas offline antes de salir."))
}

@Test func isInstructionEchoCatchesSystemPromptStructurePhrases() {
    #expect(QwenThinkingPolicy.isInstructionEcho("For greetings, welcome the user in 2-3 sentences."))
    #expect(QwenThinkingPolicy.isInstructionEcho("Answer in 4-7 concise bullet lines."))
    #expect(QwenThinkingPolicy.isInstructionEcho("Reply in the same language the user used."))
    #expect(QwenThinkingPolicy.isInstructionEcho("ask where they need travel help"))
    #expect(QwenThinkingPolicy.isInstructionEcho("Covering maps, connectivity, money, transport, language, culture, safety."))
    #expect(!QwenThinkingPolicy.isInstructionEcho("Lleva mapas offline, efectivo y una libreta con direcciones."))
}

@Test func finalizeGenerationRejectsThinkingProcessPlanLeakingAsAnswer() {
    let plan = """
    Thinking Process:
    1. Analyze the Request: user wants tips for Italy train trip.
    2. Greeting: 2-3 sentences welcoming the user.
    3. Reply: bullet list of offline advice.
    """
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: plan,
        visibleText: plan,
        thinkingText: "",
        userPrompt: "What should I save before a long train trip through Italy?"
    )
    #expect(result.answer == QwenThinkingPolicy.generationFailedMessage)
    #expect(!result.answer.contains("Thinking Process"))
    #expect(!result.answer.contains("Greeting:"))
}

@Test func finalizeGenerationRejectsForGreetingsForTravelQuestionsLeak() {
    let leak = """
    For greetings, welcome the user in 2-3 sentences and ask where they need travel help.
    For travel questions, give practical offline advice in 4-7 concise bullet lines covering maps, connectivity, money, transport, language, culture, or safety.
    """
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: leak,
        visibleText: leak,
        thinkingText: "",
        userPrompt: "Voy a Marrakech. ¿Cómo preparo mapas, dinero y transporte sin depender de internet?"
    )
    #expect(result.answer == QwenThinkingPolicy.generationFailedMessage)
    #expect(!result.answer.contains("concise bullet"))
}

@Test func finalizeGenerationRejectsGreetingBoilerplateForNonGreetingPrompt() {
    let boilerplate = "¡Hola! Soy Ultramar AI, tu asistente de viaje offline. ¿En qué puedo ayudarte hoy?"
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: boilerplate,
        visibleText: boilerplate,
        thinkingText: "",
        userPrompt: "¿Consejos para viajar a Tailandia sin datos?"
    )
    #expect(result.answer == QwenThinkingPolicy.generationFailedMessage)
}

@Test func finalizeGenerationKeepsCleanSpanishGreetingForHola() {
    let greeting = "Hola, soy Ultramar AI, tu asistente de viaje offline. ¿A dónde vas o qué necesitas planificar?"
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: greeting,
        visibleText: greeting,
        thinkingText: "",
        userPrompt: "hola"
    )
    #expect(result.answer.localizedCaseInsensitiveContains("Ultramar AI"))
    #expect(result.answer != QwenThinkingPolicy.generationFailedMessage)
}

@Test func finalizeGenerationKeepsBulletedTailandiaAdvice() {
    let advice = """
    • Descarga Google Maps offline para Bangkok y las zonas que vayas a visitar.
    • Lleva efectivo en bahts; muchos puestos y taxis no aceptan tarjeta.
    • Guarda la dirección del hotel y de la embajada por escrito y en el teléfono.
    • Aprende frases básicas en tailandés para taxi, hotel y comida.
    """
    let result = QwenThinkingPolicy.finalizeGeneration(
        raw: advice,
        visibleText: advice,
        thinkingText: "",
        userPrompt: "¿Consejos para viajar a Tailandia sin datos?"
    )
    #expect(result.answer.contains("bahts"))
    #expect(result.answer == advice.trimmingCharacters(in: .whitespacesAndNewlines))
}
