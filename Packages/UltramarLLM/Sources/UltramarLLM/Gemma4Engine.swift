import Foundation
import LlamaSwift
import UltramarCore

public enum Gemma4Error: Error, LocalizedError, Equatable {
    case modelLoadFailed
    case contextCreateFailed
    case samplerCreateFailed
    case notLoaded
    case emptyPrompt
    case templateFailed
    case tokenizeFailed
    case decodeFailed
    case visionNotSupported

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            "Failed to load Gemma 4 model."
        case .contextCreateFailed:
            "Failed to create llama.cpp context."
        case .samplerCreateFailed:
            "Failed to create sampling chain."
        case .notLoaded:
            "Gemma 4 engine is not loaded."
        case .emptyPrompt:
            "Prompt is empty."
        case .templateFailed:
            "Failed to apply chat template."
        case .tokenizeFailed:
            "Failed to tokenize prompt."
        case .decodeFailed:
            "Model decode failed."
        case .visionNotSupported:
            "Photo and audio analysis require the vision pipeline, which is not installed yet."
        }
    }
}

actor Gemma4Runtime {
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
            "engine_load_started \(UltramarLog.kv(("engine", "gemma"), ("path_suffix", pathSuffix)), privacy: .public)"
        )
        let signpost = LogSignpost.begin("engine.gemma.load")
        let start = ContinuousClock.now
        defer { LogSignpost.end("engine.gemma.load", signpost) }

        do {
            unload()
            Self.ensureBackendInitialized()

            let gpuLayers = LlamaLoadPolicy.gpuLayerCount
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = gpuLayers
            modelParams.use_mmap = true

            let path = modelURL.path
            guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
                throw Gemma4Error.modelLoadFailed
            }

            var contextParams = llama_context_default_params()
            contextParams.n_ctx = 4096
            contextParams.n_batch = 512

            guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
                llama_model_free(loadedModel)
                throw Gemma4Error.contextCreateFailed
            }

            guard let greedySampler = llama_sampler_init_greedy() else {
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                throw Gemma4Error.samplerCreateFailed
            }

            model = loadedModel
            context = loadedContext
            sampler = greedySampler

            let durationMs = LogTimer.durationMilliseconds(since: start)
            UltramarLog.engine.info(
                "engine_load_finished \(UltramarLog.kv(("engine", "gemma"), ("duration_ms", durationMs), ("gpu_layers", gpuLayers)), privacy: .public)"
            )
        } catch let error as Gemma4Error {
            UltramarLog.engine.error(
                "engine_load_failed \(UltramarLog.kv(("engine", "gemma"), ("error", String(describing: error))), privacy: .public)"
            )
            throw error
        } catch {
            UltramarLog.engine.error(
                "engine_load_failed \(UltramarLog.kv(("engine", "gemma"), ("error", error.localizedDescription)), privacy: .public)"
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
            UltramarLog.engine.info("engine_unloaded engine=gemma")
        }
    }

    var isActive: Bool {
        model != nil && context != nil && sampler != nil
    }

    func generateWithMetrics(
        prompt: String,
        maxTokens: Int = LlamaLoadPolicy.maxGenerationTokens
    ) throws -> (answer: String, tokensGenerated: Int) {
        guard let model, let context, let sampler else {
            throw Gemma4Error.notLoaded
        }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Gemma4Error.emptyPrompt
        }

        UltramarLog.engine.info(
            "inference_started \(UltramarLog.kv(("engine", "gemma"), ("prompt_chars", trimmed.count), ("max_tokens", maxTokens)), privacy: .public)"
        )
        let signpost = LogSignpost.begin("engine.gemma.generate")
        let start = ContinuousClock.now
        defer { LogSignpost.end("engine.gemma.generate", signpost) }

        do {
            LlamaContextHelpers.resetForNewGeneration(context: context, sampler: sampler)
            UltramarLog.engine.debug("inference_context_reset engine=gemma")

            let systemMessage = TravelChatPrompts.systemMessage(for: .gemmaVision)
            let formattedPrompt = try applyChatTemplate(
                model: model,
                systemMessage: systemMessage,
                userMessage: trimmed
            )

            guard let vocab = llama_model_get_vocab(model) else {
                throw Gemma4Error.tokenizeFailed
            }

            let promptTokens = try tokenize(vocab: vocab, text: formattedPrompt)
            try evaluate(tokens: promptTokens, context: context)

            let eosToken = llama_vocab_eos(vocab)
            var generatedText = ""
            var tokensGenerated = 0
            var currentPos = Int32(promptTokens.count)

            for _ in 0 ..< maxTokens {
                let nextToken = llama_sampler_sample(sampler, context, -1)
                if nextToken == eosToken {
                    break
                }

                llama_sampler_accept(sampler, nextToken)
                generatedText += tokenToPiece(vocab: vocab, token: nextToken)
                tokensGenerated += 1

                do {
                    try LlamaBatchHelpers.decode(token: nextToken, at: currentPos, context: context)
                } catch is LlamaDecodeError {
                    throw Gemma4Error.decodeFailed
                }
                currentPos += 1
            }

            let result = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let durationMs = LogTimer.durationMilliseconds(since: start)
            UltramarLog.engine.info(
                "inference_finished \(UltramarLog.kv(("engine", "gemma"), ("duration_ms", durationMs), ("tokens_generated", tokensGenerated), ("answer_chars", result.count)), privacy: .public)"
            )
            return (result, tokensGenerated)
        } catch let error as Gemma4Error {
            UltramarLog.engine.error(
                "inference_failed \(UltramarLog.kv(("engine", "gemma"), ("error", String(describing: error))), privacy: .public)"
            )
            throw error
        } catch {
            UltramarLog.engine.error(
                "inference_failed \(UltramarLog.kv(("engine", "gemma"), ("error", error.localizedDescription)), privacy: .public)"
            )
            throw error
        }
    }

    private func applyChatTemplate(
        model: OpaquePointer,
        systemMessage: String,
        userMessage: String
    ) throws -> String {
        if let templateCString = llama_model_chat_template(model, nil) {
            let template = String(cString: templateCString)
            if let formatted = applyTemplate(
                template,
                systemMessage: systemMessage,
                userMessage: userMessage
            ) {
                return formatted
            }
        }

        return chatMLFallback(systemMessage: systemMessage, userMessage: userMessage)
    }

    private func applyTemplate(
        _ template: String,
        systemMessage: String,
        userMessage: String
    ) -> String? {
        let roleSystem = strdup("system")
        let roleUser = strdup("user")
        let contentSystem = strdup(systemMessage)
        let contentUser = strdup(userMessage)
        defer {
            free(roleSystem)
            free(roleUser)
            free(contentSystem)
            free(contentUser)
        }

        var messages = [
            llama_chat_message(role: roleSystem, content: contentSystem),
            llama_chat_message(role: roleUser, content: contentUser),
        ]

        var bufferSize = max(8192, (systemMessage.count + userMessage.count) * 4)
        var buffer = [CChar](repeating: 0, count: bufferSize)

        var formattedLength = template.withCString { templatePointer in
            llama_chat_apply_template(
                templatePointer,
                &messages,
                messages.count,
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
                    &messages,
                    messages.count,
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
        """
        <|im_start|>system
        \(systemMessage)
        
        <|im_start|>user
        \(userMessage)
        
        <|im_start|>assistant
        """
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
            throw Gemma4Error.tokenizeFailed
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
                throw Gemma4Error.decodeFailed
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

public struct GemmaGenerationResult: Sendable, Equatable {
    public let answer: String
    public let tokensGenerated: Int

    public init(answer: String, tokensGenerated: Int) {
        self.answer = answer
        self.tokensGenerated = tokensGenerated
    }
}

public final class Gemma4Engine: LLMProvider, @unchecked Sendable {
    public let role: EngineRole = .gemmaVision
    public private(set) var isLoaded = false

    private let runtime = Gemma4Runtime()

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

    public func generateWithMetrics(prompt: String) async throws -> GemmaGenerationResult {
        let result = try await runtime.generateWithMetrics(prompt: prompt)
        return GemmaGenerationResult(answer: result.answer, tokensGenerated: result.tokensGenerated)
    }

    public func generate(prompt: String) async throws -> String {
        try await generateWithMetrics(prompt: prompt).answer
    }
}
