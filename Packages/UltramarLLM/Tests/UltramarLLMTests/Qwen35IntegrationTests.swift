#if os(iOS) || os(macOS)
import Foundation
import Testing
@testable import UltramarLLM

// Requires manually placing the GGUF at Application Support/UltramarAI/models/.
// Opt-in: ULTRAMAR_INTEGRATION_TESTS=1 or `make test-integration` / `make test-all`.
@Test func qwenGeneratesWhenGGUFPresent() async throws {
    guard TestRunPolicy.integrationTestsEnabled else { return }

    let modelURL = ModelPaths.qwen35ModelURL()
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
        return
    }

    let engine = Qwen35Engine()
    try await engine.load(modelURL: modelURL)
    let structured = try await engine.generateStructured(prompt: "hi")
    #expect(!structured.answer.isEmpty)
    #expect(!structured.answer.localizedCaseInsensitiveContains("<think"))
    await engine.unload()
}

@Test func qwenGeneratesMultipleTurnsWhenGGUFPresent() async throws {
    guard TestRunPolicy.integrationTestsEnabled else { return }

    let modelURL = ModelPaths.qwen35ModelURL()
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
        return
    }

    let engine = Qwen35Engine()
    try await engine.load(modelURL: modelURL)
    _ = try await engine.generateStructured(prompt: "hi")
    let second = try await engine.generateStructured(prompt: "hi")
    #expect(!second.answer.localizedCaseInsensitiveContains("<think"))
    await engine.unload()
}

@Test func qwenFinalOnlyThailandPromptWhenGGUFPresent() async throws {
    guard TestRunPolicy.integrationTestsEnabled else { return }

    let modelURL = ModelPaths.qwen35ModelURL()
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
        return
    }

    let engine = Qwen35Engine()
    try await engine.load(modelURL: modelURL)
    let structured = try await engine.generateStructured(
        prompt: "¿Consejos para viajar a Tailandia sin datos?",
        presentation: ChatPresentation(qwenReasoningMode: .finalOnly)
    )
    #expect(!structured.answer.isEmpty)
    #expect(!structured.answer.localizedCaseInsensitiveContains("Reply in the same language"))
    #expect(!structured.answer.localizedCaseInsensitiveContains("how to travel without relying"))
    let hasSpanish = structured.answer.range(of: #"[áéíóúñ¿¡]"#, options: .regularExpression) != nil
        || structured.answer.localizedCaseInsensitiveContains("tailandia")
    #expect(hasSpanish)
    #expect(structured.tokensGenerated <= 1536)
    await engine.unload()
}
#endif
