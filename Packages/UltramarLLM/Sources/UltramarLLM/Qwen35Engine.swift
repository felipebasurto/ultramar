import Foundation
import LlamaSwift
import UltramarCore

public enum Qwen35Error: Error, LocalizedError {
    case modelLoadFailed
    case contextCreateFailed
    case samplerCreateFailed
    case notLoaded
    case emptyPrompt
    case templateFailed
    case tokenizeFailed
    case decodeFailed
    case contextWindowExceeded(promptTokens: Int, maxTokens: Int, contextTokens: Int)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            "Failed to load Qwen 3.5 model."
        case .contextCreateFailed:
            "Failed to create llama.cpp context."
        case .samplerCreateFailed:
            "Failed to create sampling chain."
        case .notLoaded:
            "Qwen 3.5 engine is not loaded."
        case .emptyPrompt:
            "Prompt is empty."
        case .templateFailed:
            "Failed to apply chat template."
        case .tokenizeFailed:
            "Failed to tokenize prompt."
        case .decodeFailed:
            "Model decode failed."
        case let .contextWindowExceeded(promptTokens, maxTokens, contextTokens):
            "Prompt is too long for the local context window (\(promptTokens) prompt tokens + \(maxTokens) generation tokens > \(contextTokens))."
        }
    }
}

actor Qwen35Runtime {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    private static let backendLock = NSLock()
    private nonisolated(unsafe) static var backendInitialized = false

    private static func ensureBackendInitialized() {
        backendLock.lock()
        defer { backendLock.unlock() }
        guard !backendInitialized else { return }
        LlamaCppLogging.configureFromEnvironment()
        llama_backend_init()
        backendInitialized = true
    }

    func load(modelURL: URL) throws {
        let pathSuffix = modelURL.lastPathComponent
        UltramarLog.engine.info(
            "engine_load_started \(UltramarLog.kv(("engine", "qwen"), ("path_suffix", pathSuffix)), privacy: .public)"
        )
        let signpost = LogSignpost.begin("engine.qwen.load")
        let start = ContinuousClock.now
        defer { LogSignpost.end("engine.qwen.load", signpost) }

        do {
            unload()
            Self.ensureBackendInitialized()

            let gpuLayers = LlamaLoadPolicy.gpuLayerCount
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = gpuLayers
            modelParams.use_mmap = true

            let path = modelURL.path
            guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
                throw Qwen35Error.modelLoadFailed
            }

            var contextParams = llama_context_default_params()
            contextParams.n_ctx = UInt32(LlamaLoadPolicy.contextTokens)
            contextParams.n_batch = 512

            guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
                llama_model_free(loadedModel)
                throw Qwen35Error.contextCreateFailed
            }

            guard let qwenSampler = try? Self.makeSampler(parameters: SamplingPreset.qwenFinalOnly) else {
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                throw Qwen35Error.samplerCreateFailed
            }

            model = loadedModel
            context = loadedContext
            sampler = qwenSampler

            let durationMs = LogTimer.durationMilliseconds(since: start)
            UltramarLog.engine.info(
                "engine_load_finished \(UltramarLog.kv(("engine", "qwen"), ("duration_ms", durationMs), ("gpu_layers", gpuLayers)), privacy: .public)"
            )
        } catch let error as Qwen35Error {
            UltramarLog.engine.error(
                "engine_load_failed \(UltramarLog.kv(("engine", "qwen"), ("error", String(describing: error))), privacy: .public)"
            )
            throw error
        } catch {
            UltramarLog.engine.error(
                "engine_load_failed \(UltramarLog.kv(("engine", "qwen"), ("error", error.localizedDescription)), privacy: .public)"
            )
            throw error
        }
    }

    func unload() {
        let wasActive = isActive
        if let sampler {
            llama_sampler_free(sampler)
            self.sampler = nil
        }
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        if wasActive {
            UltramarLog.engine.info("engine_unloaded engine=qwen")
        }
    }

    var isActive: Bool {
        model != nil && context != nil && sampler != nil
    }

    private static func makeSampler(parameters: SamplingParameters) throws -> UnsafeMutablePointer<llama_sampler> {
        let chainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(chainParams) else {
            throw Qwen35Error.samplerCreateFailed
        }

        do {
            try add(llama_sampler_init_top_k(parameters.topK), to: chain)
            try add(llama_sampler_init_top_p(parameters.topP, 1), to: chain)
            try add(llama_sampler_init_min_p(parameters.minP, 1), to: chain)
            try add(
                llama_sampler_init_penalties(
                    parameters.penaltyLastN,
                    parameters.repeatPenalty,
                    parameters.frequencyPenalty,
                    parameters.presencePenalty
                ),
                to: chain
            )
            try add(llama_sampler_init_temp(parameters.temperature), to: chain)
            try add(llama_sampler_init_dist(parameters.seed), to: chain)
            return chain
        } catch {
            llama_sampler_free(chain)
            throw error
        }
    }

    private static func add(
        _ sampler: UnsafeMutablePointer<llama_sampler>?,
        to chain: UnsafeMutablePointer<llama_sampler>
    ) throws {
        guard let sampler else {
            throw Qwen35Error.samplerCreateFailed
        }
        llama_sampler_chain_add(chain, sampler)
    }

    func generate(
        prompt: String,
        presentation: ChatPresentation = ChatPresentation(),
        maxTokens: Int? = nil,
        onTokenProgress: (@Sendable (Int) -> Void)? = nil,
        onPartialAnswer: (@Sendable (String) -> Void)? = nil
    ) throws -> QwenStructuredOutput {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Qwen35Error.emptyPrompt
        }
        return try generate(
            conversation: [ChatTurn(role: .user, content: trimmed)],
            presentation: presentation,
            maxTokens: maxTokens,
            onTokenProgress: onTokenProgress,
            onPartialAnswer: onPartialAnswer
        )
    }

    func generate(
        conversation: [ChatTurn],
        presentation: ChatPresentation = ChatPresentation(),
        maxTokens: Int? = nil,
        onTokenProgress: (@Sendable (Int) -> Void)? = nil,
        onPartialAnswer: (@Sendable (String) -> Void)? = nil
    ) throws -> QwenStructuredOutput {
        let tokenLimit = maxTokens ?? LlamaLoadPolicy.maxGenerationTokens(reasoningMode: presentation.qwenReasoningMode)
        guard let model, let context else {
            throw Qwen35Error.notLoaded
        }
        if let sampler {
            llama_sampler_free(sampler)
        }
        let sampler = try Self.makeSampler(parameters: SamplingPreset.qwen(presentation.qwenReasoningMode))
        self.sampler = sampler

        guard let lastTurn = conversation.last, lastTurn.role == .user else {
            throw Qwen35Error.emptyPrompt
        }

        let trimmed = lastTurn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Qwen35Error.emptyPrompt
        }

        UltramarLog.engine.info(
            "inference_started \(UltramarLog.kv(("engine", "qwen"), ("prompt_chars", trimmed.count), ("turns", conversation.count), ("max_tokens", tokenLimit), ("reasoning_mode", presentation.qwenReasoningMode.rawValue)), privacy: .public)"
        )
        let signpost = LogSignpost.begin("engine.qwen.generate")
        let start = ContinuousClock.now
        defer { LogSignpost.end("engine.qwen.generate", signpost) }

        do {
            LlamaContextHelpers.resetForNewGeneration(context: context, sampler: sampler)
            UltramarLog.engine.debug("inference_context_reset engine=qwen")

            let systemMessage = presentation.systemPromptOverride
                ?? TravelChatPrompts.systemMessage(
                    for: TravelChatPrompts.variantForQwen(reasoningMode: presentation.qwenReasoningMode)
                )
            let generationReserve = tokenLimit
            var windowed = ChatSession(turns: conversation).windowedTurns(
                generationReserve: generationReserve
            )

            guard let vocab = llama_model_get_vocab(model) else {
                throw Qwen35Error.tokenizeFailed
            }

            let promptTokens: [llama_token]
            while true {
                let templateMessages = Self.templateMessages(
                    from: windowed,
                    reasoningMode: presentation.qwenReasoningMode
                )
                let formattedPrompt = try applyChatTemplate(
                    model: model,
                    systemMessage: systemMessage,
                    messages: templateMessages
                )
                let tokens = try tokenize(vocab: vocab, text: formattedPrompt)
                if tokens.count + tokenLimit < LlamaLoadPolicy.contextTokens {
                    promptTokens = tokens
                    break
                }
                guard windowed.count > 1 else {
                    throw Qwen35Error.contextWindowExceeded(
                        promptTokens: tokens.count,
                        maxTokens: tokenLimit,
                        contextTokens: LlamaLoadPolicy.contextTokens
                    )
                }
                Self.dropOldestExchange(from: &windowed)
            }
            try evaluate(tokens: promptTokens, context: context)

            let eosToken = llama_vocab_eos(vocab)
            var generationFilter = QwenThinkingPolicy.GenerationFilter(userPrompt: trimmed)
            var tokensGenerated = 0
            var currentPos = Int32(promptTokens.count)

            for _ in 0 ..< tokenLimit {
                let nextToken = llama_sampler_sample(sampler, context, -1)
                if nextToken == eosToken {
                    break
                }

                llama_sampler_accept(sampler, nextToken)
                let delta = generationFilter.append(tokenToPiece(vocab: vocab, token: nextToken))
                if !delta.isEmpty {
                    onPartialAnswer?(delta)
                }
                tokensGenerated += 1
                if tokensGenerated.isMultiple(of: 8) {
                    onTokenProgress?(tokensGenerated)
                }

                do {
                    try LlamaBatchHelpers.decode(token: nextToken, at: currentPos, context: context)
                } catch is LlamaDecodeError {
                    throw Qwen35Error.decodeFailed
                }
                currentPos += 1
            }

            let finalized = QwenThinkingPolicy.finalizeGeneration(
                raw: generationFilter.rawBuffer,
                visibleText: generationFilter.visibleText,
                thinkingText: generationFilter.thinkingText,
                userPrompt: trimmed
            )
            let answer = finalized.answer
            let thinking = finalized.thinking
            if answer.isEmpty, tokensGenerated > 0 {
                UltramarLog.engine.info(
                    "inference_thinking_only \(UltramarLog.kv(("engine", "qwen"), ("tokens", tokensGenerated), ("thinking_chars", thinking.count)), privacy: .public)"
                )
            }
            if tokensGenerated > 0, !tokensGenerated.isMultiple(of: 8) {
                onTokenProgress?(tokensGenerated)
            }

            let durationMs = LogTimer.durationMilliseconds(since: start)
            var finishedFields: [(String, CustomStringConvertible)] = [
                ("engine", "qwen"),
                ("duration_ms", durationMs),
                ("tokens_generated", tokensGenerated),
                ("answer_chars", answer.count),
            ]
            if !thinking.isEmpty {
                finishedFields.append(("thinking_chars", thinking.count))
            }
            UltramarLog.engine.info(
                "inference_finished \(UltramarLog.kv(finishedFields), privacy: .public)"
            )
            return QwenStructuredOutput(
                answer: answer,
                thinking: thinking,
                tokensGenerated: tokensGenerated
            )
        } catch let error as Qwen35Error {
            UltramarLog.engine.error(
                "inference_failed \(UltramarLog.kv(("engine", "qwen"), ("error", String(describing: error))), privacy: .public)"
            )
            throw error
        } catch {
            UltramarLog.engine.error(
                "inference_failed \(UltramarLog.kv(("engine", "qwen"), ("error", error.localizedDescription)), privacy: .public)"
            )
            throw error
        }
    }

    private static func templateMessages(
        from turns: [ChatTurn],
        reasoningMode: QwenReasoningMode
    ) -> [(role: String, content: String)] {
        turns.enumerated().map { index, turn in
            let role = turn.role == .user ? "user" : "assistant"
            let isLastUser = index == turns.count - 1 && turn.role == .user
            let content: String
            if isLastUser {
                content = QwenThinkingPolicy.userMessageForInference(
                    turn.content,
                    reasoningMode: reasoningMode
                )
            } else {
                content = turn.content
            }
            return (role: role, content: content)
        }
    }

    private static func dropOldestExchange(from turns: inout [ChatTurn]) {
        guard turns.count > 1 else { return }
        turns.removeFirst()
        while let first = turns.first, first.role == .assistant, turns.count > 1 {
            turns.removeFirst()
        }
    }

    private func applyChatTemplate(
        model: OpaquePointer,
        systemMessage: String,
        userMessage: String
    ) throws -> String {
        try applyChatTemplate(
            model: model,
            systemMessage: systemMessage,
            messages: [(role: "user", content: userMessage)]
        )
    }

    private func applyChatTemplate(
        model: OpaquePointer,
        systemMessage: String,
        messages: [(role: String, content: String)]
    ) throws -> String {
        if let templateCString = llama_model_chat_template(model, nil) {
            let template = String(cString: templateCString)
            if let formatted = applyTemplate(
                template,
                systemMessage: systemMessage,
                messages: messages
            ) {
                return formatted
            }
        }

        return chatMLFallback(systemMessage: systemMessage, messages: messages)
    }

    private func applyTemplate(
        _ template: String,
        systemMessage: String,
        userMessage: String
    ) -> String? {
        applyTemplate(
            template,
            systemMessage: systemMessage,
            messages: [(role: "user", content: userMessage)]
        )
    }

    private func applyTemplate(
        _ template: String,
        systemMessage: String,
        messages: [(role: String, content: String)]
    ) -> String? {
        let roleSystem = strdup("system")
        let contentSystem = strdup(systemMessage)
        var owned = [(role: UnsafeMutablePointer<CChar>?, content: UnsafeMutablePointer<CChar>?)]()
        owned.append((role: roleSystem, content: contentSystem))
        defer {
            free(roleSystem)
            free(contentSystem)
            for item in owned.dropFirst() {
                free(item.role)
                free(item.content)
            }
        }

        for message in messages {
            let role = strdup(message.role)
            let content = strdup(message.content)
            owned.append((role: role, content: content))
        }

        var chatMessages = owned.map { item in
            llama_chat_message(role: item.role, content: item.content)
        }

        let contentLength = messages.reduce(0) { $0 + $1.content.count } + systemMessage.count
        var bufferSize = max(8192, contentLength * 4)
        var buffer = [CChar](repeating: 0, count: bufferSize)

        var formattedLength = template.withCString { templatePointer in
            llama_chat_apply_template(
                templatePointer,
                &chatMessages,
                chatMessages.count,
                true,
                &buffer,
                Int32(bufferSize)
            )
        }

        if formattedLength < 0 {
            return nil
        }

        if formattedLength > bufferSize {
            bufferSize = Int(formattedLength) + 1
            buffer = [CChar](repeating: 0, count: bufferSize)
            formattedLength = template.withCString { templatePointer in
                llama_chat_apply_template(
                    templatePointer,
                    &chatMessages,
                    chatMessages.count,
                    true,
                    &buffer,
                    Int32(bufferSize)
                )
            }
            if formattedLength < 0 {
                return nil
            }
        }

        return LlamaTokenPiece.utf8String(buffer: buffer, pieceLength: formattedLength)
    }

    private func chatMLFallback(systemMessage: String, userMessage: String) -> String {
        chatMLFallback(
            systemMessage: systemMessage,
            messages: [(role: "user", content: userMessage)]
        )
    }

    private func chatMLFallback(
        systemMessage: String,
        messages: [(role: String, content: String)]
    ) -> String {
        var parts = [
            "<|im_start|>system",
            systemMessage,
        ]
        for message in messages {
            parts.append("<|im_start|>\(message.role)")
            parts.append(message.content)
        }
        parts.append("<|im_start|>assistant")
        return parts.joined(separator: "\n") + "\n"
    }

    private func tokenize(vocab: OpaquePointer, text: String) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: utf8Count + 8)

        let tokenCount = text.withCString { textPointer in
            llama_tokenize(
                vocab,
                textPointer,
                Int32(utf8Count),
                &tokens,
                Int32(tokens.count),
                true,
                true
            )
        }

        guard tokenCount > 0 else {
            throw Qwen35Error.tokenizeFailed
        }

        return Array(tokens.prefix(Int(tokenCount)))
    }

    private func evaluate(tokens: [llama_token], context: OpaquePointer) throws {
        let batchCapacity = 512
        var batch = llama_batch_init(Int32(batchCapacity), 0, 1)
        defer { llama_batch_free(batch) }

        var offset = 0
        while offset < tokens.count {
            let chunkSize = min(batchCapacity, tokens.count - offset)
            batch.n_tokens = Int32(chunkSize)

            for index in 0 ..< chunkSize {
                batch.token[index] = tokens[offset + index]
                batch.pos[index] = Int32(offset + index)
                batch.n_seq_id[index] = 1
                if let sequenceIDs = batch.seq_id, let sequenceID = sequenceIDs[index] {
                    sequenceID[0] = 0
                }
                batch.logits[index] = index == chunkSize - 1 ? 1 : 0
            }

            guard llama_decode(context, batch) == 0 else {
                throw Qwen35Error.decodeFailed
            }

            offset += chunkSize
        }
    }

    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else { return "" }
        return LlamaTokenPiece.utf8String(buffer: buffer, pieceLength: length)
    }
}

public final class Qwen35Engine: LLMProvider, @unchecked Sendable {
    public let role: EngineRole = .qwenBrain
    public private(set) var isLoaded = false

    private let runtime = Qwen35Runtime()

    public init() {}

    package func setLoadedForTesting(_ loaded: Bool) {
        isLoaded = loaded
    }

    public func load(modelURL: URL) async throws {
        try await runtime.load(modelURL: modelURL)
        isLoaded = await runtime.isActive
    }

    public func unload() async {
        await runtime.unload()
        isLoaded = false
    }

    public func generate(prompt: String) async throws -> String {
        let structured = try await generateStructured(prompt: prompt)
        return structured.answer
    }

    public func generateStructured(
        prompt: String,
        presentation: ChatPresentation = ChatPresentation(),
        onTokenProgress: (@Sendable (Int) -> Void)? = nil,
        onPartialAnswer: (@Sendable (String) -> Void)? = nil
    ) async throws -> QwenStructuredOutput {
        try await generateStructured(
            conversation: [ChatTurn(role: .user, content: prompt)],
            presentation: presentation,
            onTokenProgress: onTokenProgress,
            onPartialAnswer: onPartialAnswer
        )
    }

    public func generateStructured(
        conversation: [ChatTurn],
        presentation: ChatPresentation = ChatPresentation(),
        onTokenProgress: (@Sendable (Int) -> Void)? = nil,
        onPartialAnswer: (@Sendable (String) -> Void)? = nil
    ) async throws -> QwenStructuredOutput {
        try await runtime.generate(
            conversation: conversation,
            presentation: presentation,
            onTokenProgress: onTokenProgress,
            onPartialAnswer: onPartialAnswer
        )
    }
}
