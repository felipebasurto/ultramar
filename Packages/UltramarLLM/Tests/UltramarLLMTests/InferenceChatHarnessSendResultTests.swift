import Testing
@testable import UltramarLLM

@Test func sendResultIncludesTimingAndTokenMetadata() {
    let result = InferenceChatHarness.SendResult(
        answer: "Pack light.",
        thinking: nil,
        task: .generalChat,
        backend: .edgeQwen,
        providerLabel: "qwen",
        tokensGenerated: 42,
        durationMs: 1200
    )
    #expect(result.tokensGenerated == 42)
    #expect(result.durationMs == 1200)
    #expect(result.displayText(showThinking: false) == "Pack light.")
}
