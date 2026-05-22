import Testing
@testable import UltramarLLM

@Test func factoryUsesAppleFMWhenQwenMissingAndFMAvailable() throws {
    let qwen = Qwen35Engine()
    let gemma = Gemma4Engine()
    let fm = FoundationModelsProvider()
    let context = ProviderSelectionContext(
        task: .generalChat,
        backend: .edgeQwen,
        fm: .allEnabled,
        qwenInstalled: false,
        qwenLoaded: false,
        gemmaInstalled: false,
        gemmaLoaded: false
    )

    let provider = try LLMProviderFactory.makeProvider(
        context: context,
        qwenEngine: qwen,
        gemmaEngine: gemma,
        fmProvider: fm
    )

    #expect(provider is FoundationModelsProvider)
}

@Test func factoryThrowsWhenQwenMissingAndFMUnavailable() {
    let qwen = Qwen35Engine()
    let gemma = Gemma4Engine()
    let fm = FoundationModelsProvider()
    let context = ProviderSelectionContext(
        task: .generalChat,
        backend: .edgeQwen,
        fm: .allDisabled,
        qwenInstalled: false,
        qwenLoaded: false,
        gemmaInstalled: false,
        gemmaLoaded: false
    )

    #expect(throws: InferenceUnavailableError.qwenRequired) {
        try LLMProviderFactory.makeProvider(
            context: context,
            qwenEngine: qwen,
            gemmaEngine: gemma,
            fmProvider: fm
        )
    }
}

@Test func factoryThrowsWhenQwenPresentButUnloadedAndFMUnavailable() {
    let qwen = Qwen35Engine()
    let gemma = Gemma4Engine()
    let fm = FoundationModelsProvider()
    let context = ProviderSelectionContext(
        task: .generalChat,
        backend: .edgeQwen,
        fm: .allDisabled,
        qwenInstalled: true,
        qwenLoaded: false,
        gemmaInstalled: false,
        gemmaLoaded: false
    )

    #expect(throws: InferenceUnavailableError.qwenNotLoaded) {
        try LLMProviderFactory.makeProvider(
            context: context,
            qwenEngine: qwen,
            gemmaEngine: gemma,
            fmProvider: fm
        )
    }
}

@Test func factoryUsesQwenWhenReady() throws {
    let qwen = Qwen35Engine()
    qwen.setLoadedForTesting(true)
    let gemma = Gemma4Engine()
    let fm = FoundationModelsProvider()
    let context = ProviderSelectionContext(
        task: .generalChat,
        backend: .edgeQwen,
        fm: .allEnabled,
        qwenInstalled: true,
        qwenLoaded: true,
        gemmaInstalled: false,
        gemmaLoaded: false
    )

    let provider = try LLMProviderFactory.makeProvider(
        context: context,
        qwenEngine: qwen,
        gemmaEngine: gemma,
        fmProvider: fm
    )

    #expect(provider is Qwen35Engine)
}

@Test func factoryUsesGemmaWhenReady() throws {
    let qwen = Qwen35Engine()
    let gemma = Gemma4Engine()
    gemma.setLoadedForTesting(true)
    let fm = FoundationModelsProvider()
    let context = ProviderSelectionContext(
        task: .photoAnalysis,
        backend: .edgeGemma,
        fm: .allEnabled,
        qwenInstalled: true,
        qwenLoaded: true,
        gemmaInstalled: true,
        gemmaLoaded: true
    )

    let provider = try LLMProviderFactory.makeProvider(
        context: context,
        qwenEngine: qwen,
        gemmaEngine: gemma,
        fmProvider: fm
    )

    #expect(provider is Gemma4Engine)
}

@Test func factoryRejectsFMForToolLoopWhenQwenMissing() {
    let qwen = Qwen35Engine()
    let gemma = Gemma4Engine()
    let fm = FoundationModelsProvider()
    let context = ProviderSelectionContext(
        task: .toolLoop,
        backend: .edgeQwen,
        fm: .allEnabled,
        qwenInstalled: false,
        qwenLoaded: false,
        gemmaInstalled: false,
        gemmaLoaded: false
    )

    #expect(throws: InferenceUnavailableError.qwenRequired) {
        try LLMProviderFactory.makeProvider(
            context: context,
            qwenEngine: qwen,
            gemmaEngine: gemma,
            fmProvider: fm
        )
    }
}
