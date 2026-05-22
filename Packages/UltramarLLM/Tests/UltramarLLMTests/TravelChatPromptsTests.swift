import Testing
@testable import UltramarLLM

@Test func travelChatPromptsAreNonEmptyForAllVariants() {
    for variant in [
        TravelChatPrompts.Variant.qwenFinalOnly,
        .qwenThinking,
        .foundationModels,
        .gemmaChat,
        .gemmaVision,
    ] {
        let message = TravelChatPrompts.systemMessage(for: variant)
        #expect(!message.isEmpty)
        #expect(message.localizedCaseInsensitiveContains("travel"))
    }
}

@Test func travelChatPromptsQwenVariantMatchesSimulatorPolicy() {
    #expect(TravelChatPrompts.variantForQwen() == .qwenFinalOnly)
}

@Test func travelChatPromptsThinkingModeUsesThinkingVariant() {
    #expect(TravelChatPrompts.variantForQwen(reasoningMode: .thinking) == .qwenThinking)
}

@Test func travelChatPromptsMentionWorldwideScope() {
    let message = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    #expect(message.localizedCaseInsensitiveContains("worldwide"))
    #expect(message.localizedCaseInsensitiveContains("language"))
}

@Test func travelChatPromptsFinalOnlyDiscouragesInstructionEcho() {
    let message = TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
    #expect(message.localizedCaseInsensitiveContains("Do not reveal"))
}

@Test func travelChatPromptsSubstantiveQwenThinkingGuidance() {
    let message = TravelChatPrompts.systemMessage(for: .qwenThinking)
    #expect(message.localizedCaseInsensitiveContains("think"))
}
