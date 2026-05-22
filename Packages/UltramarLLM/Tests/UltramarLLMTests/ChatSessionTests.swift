import Testing
@testable import UltramarLLM

@Test func productChatProfileStandardDefaults() {
    let profile = ProductChatProfile.standard
    #expect(profile.task == .generalChat)
    #expect(profile.presentation.showThinking == false)
    #expect(profile.presentation.qwenReasoningMode == .finalOnly)
    #expect(profile.requiresLoadedEngine == true)
    #expect(profile.keepEngineLoadedBetweenTurns == true)
    #expect(profile.streamingEnabled == false)
}

@Test func chatSessionAppendAndClear() {
    var session = ChatSession()
    #expect(session.isEmpty)

    session.appendUserMessage("  hello  ")
    session.appendAssistantMessage("Hi there")
    #expect(session.turns.count == 2)
    #expect(session.turns[0].role == .user)
    #expect(session.turns[0].content == "hello")
    #expect(session.turns[1].role == .assistant)

    session.clear()
    #expect(session.isEmpty)
}

@Test func chatSessionIgnoresEmptyMessages() {
    var session = ChatSession()
    session.appendUserMessage("   ")
    session.appendAssistantMessage("")
    #expect(session.isEmpty)
}

@Test func chatSessionWindowDropsOldestTurns() {
    var turns: [ChatTurn] = []
    for _ in 0 ..< 40 {
        turns.append(ChatTurn(role: .user, content: String(repeating: "a", count: 200)))
        turns.append(ChatTurn(role: .assistant, content: String(repeating: "b", count: 200)))
    }
    turns.append(ChatTurn(role: .user, content: "latest question"))
    let session = ChatSession(turns: turns)

    let windowed = session.windowedTurns(
        contextTokens: 4096,
        systemReserve: 512,
        generationReserve: 1536
    )

    #expect(windowed.count < turns.count)
    #expect(windowed.last?.content == "latest question")
    #expect(windowed.last?.role == .user)
}

@Test func sendInSessionRequiresLoadedQwen() async {
    let harness = InferenceChatHarness()
    var session = ChatSession()
    let install = InferenceChatHarness.InstallSnapshot(qwenInstalled: true, gemmaInstalled: false)

    do {
        _ = try await harness.sendInSession(
            prompt: "hello",
            session: &session,
            install: install
        )
        Issue.record("Expected qwenNotLoaded")
    } catch let error as InferenceUnavailableError {
        #expect(error == .qwenNotLoaded)
        #expect(session.isEmpty)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
