import Testing
@testable import UltramarLLM

@Test func harnessSendUsesSameRoutingAsAppForToolLoop() async throws {
    let harness = InferenceChatHarness()
    let install = InferenceChatHarness.InstallSnapshot(
        qwenInstalled: true,
        gemmaInstalled: false
    )
    await #expect(throws: (any Error).self) {
        try await harness.send(
            prompt: "test",
            task: .toolLoop,
            install: install,
            fmGate: .allEnabled
        )
    }
}

@Test func harnessProviderLabelsMatchFactory() {
    let harness = InferenceChatHarness()
    #expect(InferenceChatHarness.providerLogLabel(harness.qwenEngine) == "qwen")
    #expect(InferenceChatHarness.providerLogLabel(harness.fmProvider) == "appleFM")
}
