import Foundation
import UltramarCore

/// Shared chat path for SwiftUI and CLI — mirrors `ContentView.sendPrompt()` + `generateWithFallback`.
public final class InferenceChatHarness: @unchecked Sendable {
    public let qwenEngine = Qwen35Engine()
    public let gemmaEngine = Gemma4Engine()
    public let fmProvider = FoundationModelsProvider()

    public init() {}

    public struct InstallSnapshot: Sendable, Equatable {
        public var qwenInstalled: Bool
        public var gemmaInstalled: Bool

        public init(qwenInstalled: Bool, gemmaInstalled: Bool) {
            self.qwenInstalled = qwenInstalled
            self.gemmaInstalled = gemmaInstalled
        }

        public static func current(fileManager: FileManager = .default) -> InstallSnapshot {
            InstallSnapshot(
                qwenInstalled: fileManager.fileExists(atPath: ModelPaths.qwen35ModelURL(fileManager: fileManager).path),
                gemmaInstalled: fileManager.fileExists(atPath: ModelPaths.gemma4ModelURL(fileManager: fileManager).path)
            )
        }
    }

    public struct SendResult: Sendable, Equatable {
        /// Visible answer (thinking stripped).
        public let answer: String
        /// Extracted think-block content when Qwen produced it; nil for FM/Gemma.
        public let thinking: String?
        public let task: AgentTask
        public let backend: InferenceBackend
        public let providerLabel: String
        public let tokensGenerated: Int
        public let durationMs: Int

        public init(
            answer: String,
            thinking: String?,
            task: AgentTask,
            backend: InferenceBackend,
            providerLabel: String,
            tokensGenerated: Int = 0,
            durationMs: Int = 0
        ) {
            self.answer = answer
            self.thinking = thinking
            self.task = task
            self.backend = backend
            self.providerLabel = providerLabel
            self.tokensGenerated = tokensGenerated
            self.durationMs = durationMs
        }

        public func displayText(showThinking: Bool) -> String {
            ChatResponseFormatter.format(
                answer: answer,
                thinking: thinking ?? "",
                showThinking: showThinking
            )
        }
    }

    public func loadQwenBrain(fileManager: FileManager = .default) async throws {
        UltramarLog.app.info("engine_load_requested engine=qwen")
        let from = loadedEngineLabel
        await gemmaEngine.unload()
        let modelURL = ModelPaths.qwen35ModelURL(fileManager: fileManager)
        try await qwenEngine.load(modelURL: modelURL)
        UltramarLog.app.info("engine_swap \(UltramarLog.kv(("from", from), ("to", "qwenBrain")), privacy: .public)")
    }

    public func loadGemmaVision(fileManager: FileManager = .default) async throws {
        UltramarLog.app.info("engine_load_requested engine=gemma")
        let from = loadedEngineLabel
        await qwenEngine.unload()
        let modelURL = ModelPaths.gemma4ModelURL(fileManager: fileManager)
        try await gemmaEngine.load(modelURL: modelURL)
        UltramarLog.app.info("engine_swap \(UltramarLog.kv(("from", from), ("to", "gemmaVision")), privacy: .public)")
    }

    public func unloadAll() async {
        LlamaCppLogging.ensureQuiet()
        await qwenEngine.unload()
        await gemmaEngine.unload()
    }

    public var loadedEngineLabel: String {
        if qwenEngine.isLoaded { return "qwenBrain" }
        if gemmaEngine.isLoaded { return "gemmaVision" }
        return "none"
    }

    /// Same routing + provider selection + FM fallback as the app shell.
    public func send(
        prompt: String,
        task: AgentTask = .generalChat,
        install: InstallSnapshot? = nil,
        fmGate: FMGateStatus? = nil,
        presentation: ChatPresentation = ChatPresentation(),
        onTokenProgress: (@Sendable (Int) -> Void)? = nil,
        onPartialAnswer: (@Sendable (String) -> Void)? = nil,
        fileManager: FileManager = .default
    ) async throws -> SendResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InferenceUnavailableError.qwenNotLoaded
        }

        let installSnapshot = install ?? InstallSnapshot.current(fileManager: fileManager)
        let fm = fmGate ?? FMGateDetector.current()
        let backend = InferenceRouter.route(task: task, fm: fm)

        UltramarLog.app.info(
            "chat_send \(UltramarLog.kv(("task", task.logLabel), ("backend", backend.logLabel), ("prompt_chars", trimmed.count), ("show_thinking", presentation.showThinking)), privacy: .public)"
        )

        let context = ProviderSelectionContext(
            task: task,
            backend: backend,
            fm: fm,
            qwenInstalled: installSnapshot.qwenInstalled,
            qwenLoaded: qwenEngine.isLoaded,
            gemmaInstalled: installSnapshot.gemmaInstalled,
            gemmaLoaded: gemmaEngine.isLoaded
        )

        let provider = try LLMProviderFactory.makeProvider(
            context: context,
            qwenEngine: qwenEngine,
            gemmaEngine: gemmaEngine,
            fmProvider: fmProvider
        )

        let start = ContinuousClock.now
        let generation = try await generateWithFallback(
            provider: provider,
            prompt: prompt,
            conversation: nil,
            task: task,
            context: context,
            presentation: presentation,
            onTokenProgress: onTokenProgress,
            onPartialAnswer: onPartialAnswer
        )
        let durationMs = LogTimer.durationMilliseconds(since: start)
        let label = Self.providerLogLabel(provider)
        var completedFields: [(String, CustomStringConvertible)] = [
            ("duration_ms", durationMs),
            ("provider", label),
            ("tokens_generated", generation.tokensGenerated),
            ("answer_chars", generation.answer.count),
        ]
        if let thinking = generation.thinking, !thinking.isEmpty {
            completedFields.append(("thinking_chars", thinking.count))
        }
        UltramarLog.app.info(
            "chat_completed \(UltramarLog.kv(completedFields), privacy: .public)"
        )

        return SendResult(
            answer: generation.answer,
            thinking: generation.thinking,
            task: task,
            backend: backend,
            providerLabel: label,
            tokensGenerated: generation.tokensGenerated,
            durationMs: durationMs
        )
    }

    /// Product chat path: append user turn, generate with session history, append assistant turn.
    public func sendInSession(
        prompt: String,
        session: inout ChatSession,
        profile: ProductChatProfile = .standard,
        install: InstallSnapshot? = nil,
        fmGate: FMGateStatus? = nil,
        onTokenProgress: (@Sendable (Int) -> Void)? = nil,
        onPartialAnswer: (@Sendable (String) -> Void)? = nil,
        fileManager: FileManager = .default
    ) async throws -> SendResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InferenceUnavailableError.qwenNotLoaded
        }

        let installSnapshot = install ?? InstallSnapshot.current(fileManager: fileManager)
        let fm = fmGate ?? FMGateDetector.current()
        let task = profile.task
        let presentation = profile.presentation
        let backend = InferenceRouter.route(task: task, fm: fm)

        let context = ProviderSelectionContext(
            task: task,
            backend: backend,
            fm: fm,
            qwenInstalled: installSnapshot.qwenInstalled,
            qwenLoaded: qwenEngine.isLoaded,
            gemmaInstalled: installSnapshot.gemmaInstalled,
            gemmaLoaded: gemmaEngine.isLoaded
        )

        if profile.requiresLoadedEngine {
            try validateLoadedEngine(for: backend, context: context)
        }

        session.appendUserMessage(trimmed)
        let sessionTurnCount = session.turns.count

        UltramarLog.app.info(
            "chat_send \(UltramarLog.kv(("task", task.logLabel), ("backend", backend.logLabel), ("prompt_chars", trimmed.count), ("session_turns", sessionTurnCount), ("show_thinking", presentation.showThinking)), privacy: .public)"
        )

        let provider = try LLMProviderFactory.makeProvider(
            context: context,
            qwenEngine: qwenEngine,
            gemmaEngine: gemmaEngine,
            fmProvider: fmProvider
        )

        let partialAnswerHandler: (@Sendable (String) -> Void)? =
            profile.streamingEnabled ? onPartialAnswer : nil

        let start = ContinuousClock.now
        let generation: GenerationPayload
        do {
            generation = try await generateWithFallback(
                provider: provider,
                prompt: trimmed,
                conversation: session.turns,
                task: task,
                context: context,
                presentation: presentation,
                onTokenProgress: onTokenProgress,
                onPartialAnswer: partialAnswerHandler
            )
        } catch {
            session.removeLastTurnIfUser()
            throw error
        }

        let durationMs = LogTimer.durationMilliseconds(since: start)
        let label = Self.providerLogLabel(provider)

        let answer = generation.answer.isEmpty
            ? "No response generated."
            : generation.answer
        session.appendAssistantMessage(answer)

        var completedFields: [(String, CustomStringConvertible)] = [
            ("duration_ms", durationMs),
            ("provider", label),
            ("tokens_generated", generation.tokensGenerated),
            ("session_turns", session.turns.count),
            ("answer_chars", answer.count),
        ]
        if let thinking = generation.thinking, !thinking.isEmpty {
            completedFields.append(("thinking_chars", thinking.count))
        }
        UltramarLog.app.info(
            "chat_completed \(UltramarLog.kv(completedFields), privacy: .public)"
        )

        return SendResult(
            answer: answer,
            thinking: generation.thinking,
            task: task,
            backend: backend,
            providerLabel: label,
            tokensGenerated: generation.tokensGenerated,
            durationMs: durationMs
        )
    }

    private func validateLoadedEngine(
        for backend: InferenceBackend,
        context: ProviderSelectionContext
    ) throws {
        switch backend {
        case .edgeQwen:
            guard context.qwenLoaded else {
                throw InferenceUnavailableError.qwenNotLoaded
            }
        case .edgeGemma:
            guard context.gemmaLoaded else {
                throw InferenceUnavailableError.gemmaNotLoaded
            }
        case .appleFoundationModels:
            break
        }
    }

    private struct GenerationPayload: Sendable {
        let answer: String
        let thinking: String?
        let tokensGenerated: Int
    }

    private func generateWithFallback(
        provider: any LLMProvider,
        prompt: String,
        conversation: [ChatTurn]? = nil,
        task: AgentTask,
        context: ProviderSelectionContext,
        presentation: ChatPresentation,
        onTokenProgress: (@Sendable (Int) -> Void)?,
        onPartialAnswer: (@Sendable (String) -> Void)?
    ) async throws -> GenerationPayload {
        do {
            return try await generateFromProvider(
                provider,
                prompt: prompt,
                conversation: conversation,
                presentation: presentation,
                onTokenProgress: onTokenProgress,
                onPartialAnswer: onPartialAnswer
            )
        } catch {
            if provider is FoundationModelsProvider {
                UltramarLog.routing.info("fm_runtime_fallback task=\(task.logLabel)")
                if context.qwenInstalled, context.qwenLoaded {
                    return try await generateFromProvider(
                        qwenEngine,
                        prompt: prompt,
                        conversation: conversation,
                        presentation: presentation,
                        onTokenProgress: onTokenProgress,
                        onPartialAnswer: onPartialAnswer
                    )
                }
            }
            throw error
        }
    }

    private func generateFromProvider(
        _ provider: any LLMProvider,
        prompt: String,
        conversation: [ChatTurn]? = nil,
        presentation: ChatPresentation,
        onTokenProgress: (@Sendable (Int) -> Void)?,
        onPartialAnswer: (@Sendable (String) -> Void)?
    ) async throws -> GenerationPayload {
        if let qwen = provider as? Qwen35Engine {
            let turns = conversation ?? [ChatTurn(role: .user, content: prompt)]
            let systemPrompt = presentation.systemPromptOverride
                ?? TravelChatPrompts.systemMessage(
                    for: TravelChatPrompts.variantForQwen(reasoningMode: presentation.qwenReasoningMode)
                )
            var structured = try await qwen.generateStructured(
                conversation: turns,
                presentation: presentation,
                onTokenProgress: onTokenProgress,
                onPartialAnswer: onPartialAnswer
            )
            if let reason = ChatOutputQualityGate.rejectionReason(
                answer: structured.answer,
                thinking: nil,
                userPrompt: turns.last?.content,
                systemPrompt: systemPrompt
            ) {
                UltramarLog.engine.error(
                    "quality_gate_rejected \(UltramarLog.kv(("provider", "qwen"), ("reason", reason.rawValue), ("tokens_generated", structured.tokensGenerated), ("answer_chars", structured.answer.count), ("thinking_chars", structured.thinking.count)), privacy: .public)"
                )
                var retryPresentation = presentation
                retryPresentation.qwenReasoningMode = .finalOnly
                retryPresentation.showThinking = false
                structured = try await qwen.generateStructured(
                    conversation: turns,
                    presentation: retryPresentation,
                    onTokenProgress: nil,
                    onPartialAnswer: nil
                )
                let retrySystemPrompt = retryPresentation.systemPromptOverride
                    ?? TravelChatPrompts.systemMessage(for: .qwenFinalOnly)
                if let retryReason = ChatOutputQualityGate.rejectionReason(
                    answer: structured.answer,
                    thinking: nil,
                    userPrompt: turns.last?.content,
                    systemPrompt: retrySystemPrompt
                ) {
                    UltramarLog.engine.error(
                        "quality_gate_failed_after_retry \(UltramarLog.kv(("provider", "qwen"), ("reason", retryReason.rawValue), ("tokens_generated", structured.tokensGenerated), ("answer_chars", structured.answer.count), ("thinking_chars", structured.thinking.count)), privacy: .public)"
                    )
                    throw ChatOutputQualityError.rejected(reason: retryReason)
                }
            }
            let thinking = structured.hasThinking ? structured.thinking : nil
            return GenerationPayload(
                answer: structured.answer,
                thinking: thinking,
                tokensGenerated: structured.tokensGenerated
            )
        }
        if let gemma = provider as? Gemma4Engine {
            let result = try await gemma.generateWithMetrics(prompt: prompt)
            return GenerationPayload(
                answer: result.answer,
                thinking: nil,
                tokensGenerated: result.tokensGenerated
            )
        }
        let text = try await provider.generate(prompt: prompt)
        return GenerationPayload(answer: text, thinking: nil, tokensGenerated: 0)
    }

    public static func providerLogLabel(_ provider: any LLMProvider) -> String {
        if provider is Qwen35Engine { return "qwen" }
        if provider is Gemma4Engine { return "gemma" }
        if provider is FoundationModelsProvider { return "appleFM" }
        return "unknown"
    }
}
