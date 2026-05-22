import UltramarCore

public enum LLMProviderFactory {
    public static func makeProvider(
        context: ProviderSelectionContext,
        qwenEngine: Qwen35Engine,
        gemmaEngine: Gemma4Engine,
        fmProvider: FoundationModelsProvider
    ) throws -> any LLMProvider {
        switch context.backend {
        case .edgeQwen:
            if context.qwenInstalled, context.qwenLoaded {
                logSelection(backend: context.backend, provider: "qwen", reason: "ready")
                return qwenEngine
            }
            if allowsFMFallback(for: context.task), context.fm.isAvailable {
                logSelection(backend: context.backend, provider: "appleFM", reason: qwenFallbackReason(context))
                return fmProvider
            }
            if !context.qwenInstalled {
                logSelection(backend: context.backend, provider: "error", reason: "model_not_installed")
                throw InferenceUnavailableError.qwenRequired
            }
            logSelection(backend: context.backend, provider: "error", reason: "model_not_loaded")
            throw InferenceUnavailableError.qwenNotLoaded

        case .edgeGemma:
            if context.gemmaInstalled, context.gemmaLoaded {
                logSelection(backend: context.backend, provider: "gemma", reason: "ready")
                return gemmaEngine
            }
            if !context.gemmaInstalled {
                logSelection(backend: context.backend, provider: "error", reason: "model_not_installed")
                throw InferenceUnavailableError.gemmaRequired
            }
            logSelection(backend: context.backend, provider: "error", reason: "model_not_loaded")
            throw InferenceUnavailableError.gemmaNotLoaded

        case .appleFoundationModels:
            if context.fm.isAvailable {
                logSelection(backend: context.backend, provider: "appleFM", reason: "ready")
                return fmProvider
            }
            if context.qwenInstalled, context.qwenLoaded {
                logSelection(backend: context.backend, provider: "qwen", reason: "fm_unavailable")
                return qwenEngine
            }
            logSelection(backend: context.backend, provider: "error", reason: "no_backend")
            throw InferenceUnavailableError.noBackendAvailable
        }
    }

    public static func engineRole(for backend: InferenceBackend) -> EngineRole {
        switch backend {
        case .edgeGemma:
            return .gemmaVision
        case .edgeQwen, .appleFoundationModels:
            return .qwenBrain
        }
    }

    public static func allowsFMFallback(for task: AgentTask) -> Bool {
        switch task {
        case .generalChat, .summary, .generable:
            return true
        case .toolLoop, .safety, .photoAnalysis, .audioAnalysis:
            return false
        }
    }

    private static func qwenFallbackReason(_ context: ProviderSelectionContext) -> String {
        if !context.qwenInstalled {
            return "model_not_installed"
        }
        return "model_not_loaded"
    }

    private static func logSelection(backend: InferenceBackend, provider: String, reason: String) {
        UltramarLog.routing.info(
            "provider_selected \(UltramarLog.kv(("backend", backend.logLabel), ("provider", provider), ("reason", reason)), privacy: .public)"
        )
    }
}
