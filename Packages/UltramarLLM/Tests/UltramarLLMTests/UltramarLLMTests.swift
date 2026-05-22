import Testing
@testable import UltramarLLM

@Test func gemmaEngineReportsNotLoadedByDefault() {
    let engine = Gemma4Engine()
    #expect(engine.role == .gemmaVision)
    #expect(engine.isLoaded == false)
}

@Test func gemmaEngineThrowsWhenNotLoaded() async {
    let engine = Gemma4Engine()

    do {
        _ = try await engine.generate(prompt: "Describe this menu")
        Issue.record("Expected not loaded error")
    } catch let error as Gemma4Error {
        #expect(error == .notLoaded)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
