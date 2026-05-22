import UltramarCore

public protocol LLMProvider: Sendable {
    var role: EngineRole { get }
    var isLoaded: Bool { get }
    func generate(prompt: String) async throws -> String
}
