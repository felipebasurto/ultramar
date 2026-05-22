import Foundation
import UltramarCore
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FoundationModelsError: Error, LocalizedError {
    case unavailable
    case emptyPrompt
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Intelligence is not available on this device."
        case .emptyPrompt:
            "Prompt is empty."
        case .generationFailed(let message):
            "Apple Intelligence failed: \(message)"
        }
    }
}

public struct FoundationModelsProvider: LLMProvider, Sendable {
    public let role: EngineRole = .none
    public var isLoaded: Bool { true }

    public init() {}

    public func generate(prompt: String) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FoundationModelsError.emptyPrompt
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw FoundationModelsError.unavailable
        }

        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw FoundationModelsError.unavailable
        }

        UltramarLog.engine.info(
            "inference_started \(UltramarLog.kv(("engine", "appleFM"), ("prompt_chars", trimmed.count)), privacy: .public)"
        )
        let start = ContinuousClock.now

        do {
            let session = LanguageModelSession(
                instructions: TravelChatPrompts.systemMessage(for: .foundationModels)
            )
            let response = try await session.respond(to: trimmed)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let durationMs = LogTimer.durationMilliseconds(since: start)
            UltramarLog.engine.info(
                "inference_finished \(UltramarLog.kv(("engine", "appleFM"), ("duration_ms", durationMs), ("answer_chars", result.count)), privacy: .public)"
            )
            return result
        } catch {
            UltramarLog.engine.error(
                "inference_failed \(UltramarLog.kv(("engine", "appleFM"), ("error", error.localizedDescription)), privacy: .public)"
            )
            throw FoundationModelsError.generationFailed(error.localizedDescription)
        }
        #else
        throw FoundationModelsError.unavailable
        #endif
    }
}
