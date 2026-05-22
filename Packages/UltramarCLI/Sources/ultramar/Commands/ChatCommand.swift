import ArgumentParser
import Foundation
import UltramarCore
import UltramarLLM

struct Chat: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Run local chat via server mode or embedded inference.",
        usage: """
        Examples:
          ultramar chat --backend server --engine qwen
          ultramar chat --backend server --prompt "Say hello" --engine qwen
          ultramar chat --backend server --prompts-file ./prompts.txt --engine qwen --format json
          ultramar chat --backend embedded --interactive --engine qwen
        """,
        discussion: """
        Server mode is the macOS CLI default and expects llama-server at --base-url.
        Embedded mode keeps the legacy in-process llama.cpp path for iOS parity and debugging.
        Batch (--prompts-file, repeated --prompt, --stdin-lines) reuses the selected backend for all prompts.
        """
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Prompt text. Repeat for batch runs.")
    var prompt: [String] = []

    @Option(name: .long, help: "File with one prompt per line (# starts a comment).")
    var promptsFile: String?

    @Flag(name: .long, help: "Read one prompt from stdin (entire stream).")
    var stdin: Bool = false

    @Flag(name: .long, help: "Read one prompt per line from stdin.")
    var stdinLines: Bool = false

    @Flag(name: [.customShort("i"), .long], help: "Interactive chat REPL (also default with no prompts in a TTY).")
    var interactive: Bool = false

    @Option(name: .long, help: "Engine: qwen, gemma, or auto (app routing; requires load for edge).")
    var engine: EngineOption.ChatEngine = .auto

    @Option(name: .long, help: "Backend: server (default) or embedded.")
    var backend: ChatBackendOption = .server

    @Option(name: .long, help: "OpenAI-compatible base URL for server backend.")
    var baseURL: String = OpenAICompatibleLocalBackend.defaultBaseURL.absoluteString

    @Option(name: .long, help: "Agent task for routing.")
    var task: AgentTaskOption = .generalChat

    @Option(name: .long, help: "Explicit GGUF path (loads into harness qwen/gemma engine).")
    var modelPath: String?

    @Option(name: .long, help: "UTF-8 file with a custom system prompt for this chat run.")
    var systemPromptFile: String?

    @Flag(name: .long, help: "Deprecated; CLI unloads cleanly before process exit. Use REPL or batch to avoid reloads.")
    var keepLoaded: Bool = false

    @Flag(name: .long, help: "Deprecated; product chat unloads cleanly when the CLI process exits.")
    var unload: Bool = false

    @Flag(name: .long, help: "Include Qwen think blocks in output (hidden by default).")
    var showThinking: Bool = false

    @Flag(name: .long, help: "Stream answer tokens to stdout as they are generated (single prompt only).")
    var stream: Bool = false

    @Flag(name: .long, help: "Print Qwen thinking section on stderr after timing (requires --show-thinking).")
    var verbose: Bool = false

    @Flag(name: .long, help: "Deprecated alias for final-only /no_think mode (now the default).")
    var fast: Bool = false

    @Flag(name: .long, help: "Debug Qwen thinking mode with visible think blocks in output.")
    var thinking: Bool = false

    @Flag(name: .long, help: "Print token progress to stderr during generation (debug only).")
    var progress: Bool = false

    func validate() throws {
        if stdin && stdinLines {
            throw ValidationError("Use either --stdin or --stdin-lines, not both.")
        }

        let hasPromptSources = !prompt.isEmpty || promptsFile != nil || stdin || stdinLines
        if interactive && hasPromptSources {
            throw ValidationError("Use --interactive alone, not with --prompt, --prompts-file, --stdin, or --stdin-lines.")
        }
        if backend == .server, modelPath != nil {
            throw ValidationError("Use --model-path only with --backend embedded.")
        }

        if !hasPromptSources,
           !ChatInteractiveLoop.shouldRun(interactiveFlag: interactive, hasPromptSources: hasPromptSources)
        {
            throw ValidationError(
                """
                No prompts specified.
                Examples:
                  ultramar chat --engine qwen
                  ultramar chat --interactive --engine qwen
                  ultramar chat --prompt "Your question" --engine qwen
                """
            )
        }
    }

    func run() async throws {
        let hasPromptSources = !prompt.isEmpty || promptsFile != nil || stdin || stdinLines
        if ChatInteractiveLoop.shouldRun(interactiveFlag: interactive, hasPromptSources: hasPromptSources) {
            if backend == .server {
                try await runServerInteractive()
            } else {
                try await runInteractive()
            }
            return
        }

        let stdinData: Data
        if stdin || stdinLines {
            stdinData = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            stdinData = Data()
        }

        let prompts: [String]
        do {
            prompts = try ChatPromptBatch.resolve(
                commandPrompts: prompt,
                promptsFile: promptsFile,
                useStdin: stdin,
                useStdinLines: stdinLines,
                stdinData: stdinData
            )
        } catch let error as ChatPromptBatch.Error {
            CLIOutput.printError(
                error.localizedDescription,
                hint: promptHint,
                format: global.format
            )
        }

        if stream && prompts.count > 1 {
            CLIOutput.printError(
                "--stream supports a single prompt only.",
                hint: "Remove --stream or pass one prompt.",
                format: global.format
            )
        }

        if backend == .server {
            try await runServerBatch(prompts: prompts)
            return
        }

        let harness = InferenceChatHarness()
        let fileManager = FileManager.default
        let modelsDir = try global.resolvedModelsDirectory(fileManager: fileManager)
        let install = InstallSnapshot(
            qwenInstalled: fileManager.fileExists(
                atPath: CLIPaths.modelFileURL(artifact: ModelCatalog.qwenBrain, modelsDirectory: modelsDir).path
            ),
            gemmaInstalled: fileManager.fileExists(
                atPath: CLIPaths.modelFileURL(artifact: ModelCatalog.gemmaVision, modelsDirectory: modelsDir).path
            )
        )

        do {
            let useStream = stream && global.format == .text && prompts.count == 1
            let reasoningMode = thinking ? QwenReasoningMode.thinking : .finalOnly
            let systemPromptOverride = try loadSystemPromptOverride(fileManager: fileManager)
            FileHandle.standardError.write(Data("Loading model…\n".utf8))

            let loadStart = ContinuousClock.now
            try await prepareHarness(harness: harness, install: install, fileManager: fileManager)
            let loadMs = LogTimer.durationMilliseconds(since: loadStart)

            var results: [ChatTurnResult] = []
            for (index, promptText) in prompts.enumerated() {
                let turn = try await runTurn(
                    harness: harness,
                    install: install,
                    promptText: promptText,
                    index: index,
                    total: prompts.count,
                    loadMs: loadMs,
                    reasoningMode: reasoningMode,
                    systemPromptOverride: systemPromptOverride,
                    useStream: useStream,
                    fileManager: fileManager
                )
                results.append(turn)
            }

            await StderrSilencer.withSilencedStderr {
                await harness.unloadAll()
            }

            emitBatchOutput(results: results, loadMs: loadMs)
        } catch let error as CLIError {
            await StderrSilencer.withSilencedStderr {
                await harness.unloadAll()
            }
            CLIOutput.printError(error.localizedDescription, hint: error.hint, format: global.format)
        } catch {
            await StderrSilencer.withSilencedStderr {
                await harness.unloadAll()
            }
            CLIOutput.printError(
                error.localizedDescription,
                hint: promptHint,
                format: global.format
            )
        }
    }

    private var promptHint: String {
        "make qwen-server  |  ultramar chat --backend server --prompt \"...\" --engine qwen"
    }

    private var showThinkingOutput: Bool {
        showThinking || thinking
    }

    private func runServerInteractive() async throws {
        if global.format == .json {
            CLIOutput.printError(
                "Interactive chat requires --format text.",
                hint: "ultramar chat --backend server --engine qwen",
                format: global.format
            )
        }
        if stream {
            CLIOutput.printError(
                "--stream is not supported in interactive chat.",
                hint: "Remove --stream.",
                format: global.format
            )
        }

        let fileManager = FileManager.default
        do {
            ChatInteractiveLoop.printBanner()
            let orchestrator = try makeServerOrchestrator()
            try await orchestrator.prepare()
            FileHandle.standardError.write(Data("Conectado a \(baseURL)\n\n".utf8))

            var messages: [ChatMessage] = []
            var systemPrompt: String? = try loadSystemPromptOverride(fileManager: fileManager)
                ?? defaultSystemPromptForServer()
            let turnCount = try await ChatInteractiveLoop.run(
                orchestrator: orchestrator,
                messages: &messages,
                systemPrompt: &systemPrompt,
                reasoningMode: thinking ? .thinking : .finalOnly,
                showThinkingInOutput: showThinkingOutput,
                progress: progress,
                verbose: verbose,
                fileManager: fileManager
            )
            await orchestrator.shutdown()

            if turnCount > 0 {
                FileHandle.standardError.write(Data("Sesión terminada.\n".utf8))
            }
        } catch let error as CLIError {
            CLIOutput.printError(error.localizedDescription, hint: error.hint, format: global.format)
        } catch {
            CLIOutput.printError(error.localizedDescription, hint: promptHint, format: global.format)
        }
    }

    private func runServerBatch(prompts: [String]) async throws {
        let fileManager = FileManager.default
        do {
            let orchestrator = try makeServerOrchestrator()
            try await orchestrator.prepare()
            let systemPrompt = try loadSystemPromptOverride(fileManager: fileManager)
                ?? defaultSystemPromptForServer()
            let useStream = stream && global.format == .text && prompts.count == 1

            var results: [ServerChatTurnResult] = []
            for (index, promptText) in prompts.enumerated() {
                let result = try await runServerTurn(
                    orchestrator: orchestrator,
                    promptText: promptText,
                    index: index,
                    total: prompts.count,
                    systemPrompt: systemPrompt,
                    useStream: useStream
                )
                results.append(result)
            }
            await orchestrator.shutdown()
            emitServerBatchOutput(results: results)
        } catch let error as CLIError {
            CLIOutput.printError(error.localizedDescription, hint: error.hint, format: global.format)
        } catch {
            CLIOutput.printError(error.localizedDescription, hint: promptHint, format: global.format)
        }
    }

    private struct ServerChatTurnResult: Sendable {
        let index: Int
        let prompt: String
        let response: ChatResponse
    }

    private func runServerTurn(
        orchestrator: ChatOrchestrator,
        promptText: String,
        index: Int,
        total: Int,
        systemPrompt: String?,
        useStream: Bool
    ) async throws -> ServerChatTurnResult {
        if total > 1 {
            FileHandle.standardError.write(
                Data("Prompt \(index + 1)/\(total) (\(promptText.count) chars)…\n".utf8)
            )
        }

        let request = ChatRequest(
            messages: [ChatMessage(role: .user, content: promptText)],
            systemPrompt: systemPrompt,
            sampling: thinking ? SamplingPreset.qwenThinking : SamplingPreset.qwenFinalOnly,
            reasoningMode: thinking ? .thinking : .finalOnly,
            maxTokens: thinking ? 1536 : 512,
            showThinking: showThinkingOutput,
            task: task.task
        )

        let response: ChatResponse
        if useStream {
            var finalResponse: ChatResponse?
            for try await event in orchestrator.stream(request) {
                switch event {
                case .token(let delta):
                    FileHandle.standardOutput.write(Data(delta.utf8))
                case .final(let final):
                    finalResponse = final
                default:
                    break
                }
            }
            FileHandle.standardOutput.write(Data("\n".utf8))
            guard let finalResponse else {
                throw OpenAICompatibleLocalBackendError.missingChoice
            }
            response = finalResponse
        } else {
            response = try await orchestrator.send(request)
        }

        let timing = CLITimingSummary(
            engine: response.providerLabel,
            loadDurationMs: 0,
            inferenceDurationMs: response.durationMs,
            tokensGenerated: response.tokens
        )

        switch global.format {
        case .text:
            if total > 1 {
                Swift.print("=== [\(index + 1)/\(total)] ===")
            }
            if !useStream {
                let display = response.displayText(showThinking: showThinkingOutput)
                Swift.print(display.isEmpty ? "No response generated." : display)
                if total > 1, index < total - 1 {
                    Swift.print("")
                }
            }
            CLITimingSummary.writeStderrLine(timing)
            if verbose {
                Self.printThinkingFooter(response: response, showThinking: showThinkingOutput)
            }
        case .json:
            break
        }

        return ServerChatTurnResult(index: index, prompt: promptText, response: response)
    }

    private func emitServerBatchOutput(results: [ServerChatTurnResult]) {
        guard global.format == .json else {
            if results.count > 1 {
                let totalTokens = results.reduce(0) { $0 + $1.response.tokens }
                let totalInferenceMs = results.reduce(0) { $0 + $1.response.durationMs }
                FileHandle.standardError.write(
                    Data(
                        """
                        Batch: \(results.count) prompts | \
                        \(totalTokens) tokens | \
                        inference \(CLITimingSummary.seconds(fromMilliseconds: totalInferenceMs))s | \
                        load 0.0s

                        """.utf8
                    )
                )
            }
            return
        }

        if results.count == 1, let turn = results.first {
            emitSingleServerJSON(turn: turn)
            CLITimingSummary.writeStderrLine(
                CLITimingSummary(
                    engine: turn.response.providerLabel,
                    loadDurationMs: 0,
                    inferenceDurationMs: turn.response.durationMs,
                    tokensGenerated: turn.response.tokens
                )
            )
            return
        }

        let totalInferenceMs = results.reduce(0) { $0 + $1.response.durationMs }
        let totalTokens = results.reduce(0) { $0 + $1.response.tokens }
        let fields: [String: JSONValue] = [
            "ok": .bool(true),
            "batch": .bool(true),
            "count": .int(results.count),
            "load_duration_ms": .int(0),
            "total_duration_ms": .int(totalInferenceMs),
            "total_inference_duration_ms": .int(totalInferenceMs),
            "total_tokens_generated": .int(totalTokens),
            "results": .array(results.map { serverTurnJSON($0) }),
        ]
        CLIOutput.print(fields, format: .json)
        FileHandle.standardError.write(
            Data(
                """
                Batch timing: \(results.count) prompts | \
                load 0.0s | \
                inference \(CLITimingSummary.seconds(fromMilliseconds: totalInferenceMs))s

                """.utf8
            )
        )
    }

    private func emitSingleServerJSON(turn: ServerChatTurnResult) {
        let response = turn.response
        let display = response.displayText(showThinking: showThinkingOutput)
        var fields: [String: JSONValue] = [
            "ok": .bool(true),
            "engine": .string(response.providerLabel),
            "backend": .string(response.backend.rawValue),
            "task": .string(task.task.logLabel),
            "answer": .string(response.answer),
            "show_thinking": .bool(showThinkingOutput),
            "text": .string(display),
            "prompt_chars": .int(turn.prompt.count),
        ]
        let timing = CLITimingSummary(
            engine: response.providerLabel,
            loadDurationMs: 0,
            inferenceDurationMs: response.durationMs,
            tokensGenerated: response.tokens
        )
        for (key, value) in timing.jsonFields {
            fields[key] = value
        }
        if let thinking = response.hiddenReasoning, !thinking.isEmpty {
            fields["thinking"] = .string(thinking)
        }
        CLIOutput.print(fields, format: .json)
    }

    private func serverTurnJSON(_ turn: ServerChatTurnResult) -> JSONValue {
        let response = turn.response
        var fields: [String: JSONValue] = [
            "index": .int(turn.index),
            "ok": .bool(true),
            "prompt": .string(turn.prompt),
            "prompt_chars": .int(turn.prompt.count),
            "engine": .string(response.providerLabel),
            "backend": .string(response.backend.rawValue),
            "task": .string(task.task.logLabel),
            "answer": .string(response.answer),
            "text": .string(response.displayText(showThinking: showThinkingOutput)),
            "duration_ms": .int(response.durationMs),
            "tokens_generated": .int(response.tokens),
        ]
        if let thinking = response.hiddenReasoning, !thinking.isEmpty {
            fields["thinking"] = .string(thinking)
        }
        if let tokensPerSecond = CLITimingSummary.tokensPerSecond(
            tokens: response.tokens,
            inferenceMs: response.durationMs
        ) {
            fields["tokens_per_second"] = .double(tokensPerSecond)
        }
        return .object(fields)
    }

    private func makeServerOrchestrator() throws -> ChatOrchestrator {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else {
            throw OpenAICompatibleLocalBackendError.invalidBaseURL(baseURL)
        }
        let profile: ModelProfile
        switch engine {
        case .gemma:
            profile = .gemmaServer()
        case .qwen, .auto:
            profile = .qwenServer()
        }
        return ChatOrchestrator.server(baseURL: url, profile: profile)
    }

    private func defaultSystemPromptForServer() -> String {
        switch engine {
        case .gemma:
            TravelChatPrompts.systemMessage(for: .gemmaChat)
        case .qwen, .auto:
            TravelChatPrompts.systemMessage(
                for: TravelChatPrompts.variantForQwen(reasoningMode: thinking ? .thinking : .finalOnly)
            )
        }
    }

    private func runInteractive() async throws {
        if global.format == .json {
            CLIOutput.printError(
                "Interactive chat requires --format text.",
                hint: "ultramar chat --engine qwen",
                format: global.format
            )
        }
        if stream {
            CLIOutput.printError(
                "--stream is not supported in interactive chat.",
                hint: "Remove --stream.",
                format: global.format
            )
        }
        if fast {
            CLIOutput.printError(
                "--fast is for dev/harness one-shot mode only.",
                hint: "ultramar chat --engine qwen",
                format: global.format
            )
        }
        switch engine {
        case .qwen, .gemma:
            break
        case .auto:
            CLIOutput.printError(
                "Product chat requires --engine qwen or --engine gemma.",
                hint: "ultramar chat --engine qwen",
                format: global.format
            )
        }

        let harness = InferenceChatHarness()
        let fileManager = FileManager.default
        let modelsDir = try global.resolvedModelsDirectory(fileManager: fileManager)
        let install = InstallSnapshot(
            qwenInstalled: fileManager.fileExists(
                atPath: CLIPaths.modelFileURL(artifact: ModelCatalog.qwenBrain, modelsDirectory: modelsDir).path
            ),
            gemmaInstalled: fileManager.fileExists(
                atPath: CLIPaths.modelFileURL(artifact: ModelCatalog.gemmaVision, modelsDirectory: modelsDir).path
            )
        )

        do {
            ChatInteractiveLoop.printBanner()
            let loadStart = ContinuousClock.now
            try await prepareHarness(harness: harness, install: install, fileManager: fileManager)
            let loadMs = LogTimer.durationMilliseconds(since: loadStart)
            FileHandle.standardError.write(
                Data("Listo en \(CLITimingSummary.seconds(fromMilliseconds: loadMs))s\n\n".utf8)
            )

            var session = ChatSession()
            var profile = ProductChatProfile.standard
            profile.presentation.showThinking = showThinking || thinking
            profile.presentation.qwenReasoningMode = thinking ? .thinking : .finalOnly
            profile.presentation.systemPromptOverride = try loadSystemPromptOverride(fileManager: fileManager)

            let turnCount = try await ChatInteractiveLoop.run(
                harness: harness,
                session: &session,
                profile: profile,
                install: install,
                showThinkingInOutput: profile.presentation.showThinking,
                progress: progress,
                verbose: verbose,
                fileManager: fileManager
            )

            await StderrSilencer.withSilencedStderr {
                await harness.unloadAll()
            }

            if turnCount > 0 {
                FileHandle.standardError.write(Data("Sesión terminada.\n".utf8))
            }
        } catch let error as CLIError {
            await StderrSilencer.withSilencedStderr {
                await harness.unloadAll()
            }
            CLIOutput.printError(error.localizedDescription, hint: error.hint, format: global.format)
        } catch {
            await StderrSilencer.withSilencedStderr {
                await harness.unloadAll()
            }
            CLIOutput.printError(error.localizedDescription, hint: promptHint, format: global.format)
        }
    }

    private struct ChatTurnResult: Sendable {
        let index: Int
        let prompt: String
        let sendResult: InferenceChatHarness.SendResult
    }

    private func runTurn(
        harness: InferenceChatHarness,
        install: InstallSnapshot,
        promptText: String,
        index: Int,
        total: Int,
        loadMs: Int,
        reasoningMode: QwenReasoningMode,
        systemPromptOverride: String?,
        useStream: Bool,
        fileManager: FileManager
    ) async throws -> ChatTurnResult {
        if total > 1 {
            FileHandle.standardError.write(
                Data("Prompt \(index + 1)/\(total) (\(promptText.count) chars)…\n".utf8)
            )
        }

        let streamState = StreamOutputState(enabled: useStream)
        let progressReporter = CLIProgressReporter(enabled: progress)
        let onTokenProgress: (@Sendable (Int) -> Void)? = progress
            ? { @Sendable count in progressReporter.report(tokens: count) }
            : nil
        let onPartialAnswer: (@Sendable (String) -> Void)? = useStream
            ? { @Sendable delta in streamState.write(delta) }
            : nil

        let sendResult = try await harness.send(
            prompt: promptText,
            task: task.task,
            install: install,
            presentation: ChatPresentation(
                showThinking: showThinking || thinking,
                qwenReasoningMode: reasoningMode,
                systemPromptOverride: systemPromptOverride
            ),
            onTokenProgress: onTokenProgress,
            onPartialAnswer: onPartialAnswer,
            fileManager: fileManager
        )

        progressReporter.finish()

        let timing = CLITimingSummary(
            engine: sendResult.providerLabel,
            loadDurationMs: index == 0 ? loadMs : 0,
            inferenceDurationMs: sendResult.durationMs,
            tokensGenerated: sendResult.tokensGenerated
        )

        switch global.format {
        case .text:
            if total > 1 {
                Swift.print("=== [\(index + 1)/\(total)] ===")
            }
            let display = sendResult.displayText(showThinking: showThinkingOutput)
            if useStream {
                streamState.finish(fallbackAnswer: sendResult.answer)
            } else {
                let text = display.isEmpty ? "No response generated." : display
                Swift.print(text)
                if total > 1, index < total - 1 {
                    Swift.print("")
                }
            }
            CLITimingSummary.writeStderrLine(timing)
            if verbose {
                Self.printThinkingFooter(sendResult: sendResult, showThinking: showThinkingOutput)
            }
        case .json:
            break
        }

        return ChatTurnResult(index: index, prompt: promptText, sendResult: sendResult)
    }

    private func emitBatchOutput(results: [ChatTurnResult], loadMs: Int) {
        guard global.format == .json else {
            if results.count > 1 {
                let totalTokens = results.reduce(0) { $0 + $1.sendResult.tokensGenerated }
                let totalInferenceMs = results.reduce(0) { $0 + $1.sendResult.durationMs }
                FileHandle.standardError.write(
                    Data(
                        """
                        Batch: \(results.count) prompts | \
                        \(totalTokens) tokens | \
                        inference \(CLITimingSummary.seconds(fromMilliseconds: totalInferenceMs))s | \
                        load \(CLITimingSummary.seconds(fromMilliseconds: loadMs))s

                        """.utf8
                    )
                )
            }
            return
        }

        if results.count == 1, let turn = results.first {
            emitSingleJSON(turn: turn, loadMs: loadMs)
            CLITimingSummary.writeStderrLine(
                CLITimingSummary(
                    engine: turn.sendResult.providerLabel,
                    loadDurationMs: loadMs,
                    inferenceDurationMs: turn.sendResult.durationMs,
                    tokensGenerated: turn.sendResult.tokensGenerated
                )
            )
            return
        }

        let totalInferenceMs = results.reduce(0) { $0 + $1.sendResult.durationMs }
        let totalTokens = results.reduce(0) { $0 + $1.sendResult.tokensGenerated }
        let fields: [String: JSONValue] = [
            "ok": .bool(true),
            "batch": .bool(true),
            "count": .int(results.count),
            "load_duration_ms": .int(loadMs),
            "total_duration_ms": .int(loadMs + totalInferenceMs),
            "total_inference_duration_ms": .int(totalInferenceMs),
            "total_tokens_generated": .int(totalTokens),
            "results": .array(results.map { turnJSON($0) }),
        ]
        CLIOutput.print(fields, format: .json)
        FileHandle.standardError.write(
            Data(
                """
                Batch timing: \(results.count) prompts | \
                load \(CLITimingSummary.seconds(fromMilliseconds: loadMs))s | \
                inference \(CLITimingSummary.seconds(fromMilliseconds: totalInferenceMs))s

                """.utf8
            )
        )
    }

    private func emitSingleJSON(turn: ChatTurnResult, loadMs: Int) {
        let sendResult = turn.sendResult
        let display = sendResult.displayText(showThinking: showThinkingOutput)
        var fields: [String: JSONValue] = [
            "ok": .bool(true),
            "engine": .string(sendResult.providerLabel),
            "backend": .string(sendResult.backend.logLabel),
            "task": .string(sendResult.task.logLabel),
            "answer": .string(sendResult.answer),
            "show_thinking": .bool(showThinkingOutput),
            "text": .string(display),
            "prompt_chars": .int(turn.prompt.count),
        ]
        let timing = CLITimingSummary(
            engine: sendResult.providerLabel,
            loadDurationMs: loadMs,
            inferenceDurationMs: sendResult.durationMs,
            tokensGenerated: sendResult.tokensGenerated
        )
        for (key, value) in timing.jsonFields {
            fields[key] = value
        }
        if let thinking = sendResult.thinking, !thinking.isEmpty {
            fields["thinking"] = .string(thinking)
        }
        CLIOutput.print(fields, format: .json)
    }

    private func turnJSON(_ turn: ChatTurnResult) -> JSONValue {
        let sendResult = turn.sendResult
        var fields: [String: JSONValue] = [
            "index": .int(turn.index),
            "ok": .bool(true),
            "prompt": .string(turn.prompt),
            "prompt_chars": .int(turn.prompt.count),
            "engine": .string(sendResult.providerLabel),
            "backend": .string(sendResult.backend.logLabel),
            "task": .string(sendResult.task.logLabel),
            "answer": .string(sendResult.answer),
            "text": .string(sendResult.displayText(showThinking: showThinkingOutput)),
            "duration_ms": .int(sendResult.durationMs),
            "tokens_generated": .int(sendResult.tokensGenerated),
        ]
        if let thinking = sendResult.thinking, !thinking.isEmpty {
            fields["thinking"] = .string(thinking)
        }
        if let tokensPerSecond = CLITimingSummary.tokensPerSecond(
            tokens: sendResult.tokensGenerated,
            inferenceMs: sendResult.durationMs
        ) {
            fields["tokens_per_second"] = .double(tokensPerSecond)
        }
        return .object(fields)
    }

    private static func printThinkingFooter(
        sendResult: InferenceChatHarness.SendResult,
        showThinking: Bool
    ) {
        guard showThinking, let thinking = sendResult.thinking, !thinking.isEmpty else { return }
        FileHandle.standardError.write(Data("--- Thinking ---\n".utf8))
        FileHandle.standardError.write(Data(thinking.utf8))
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private static func printThinkingFooter(
        response: ChatResponse,
        showThinking: Bool
    ) {
        guard showThinking, let thinking = response.hiddenReasoning, !thinking.isEmpty else { return }
        FileHandle.standardError.write(Data("--- Thinking ---\n".utf8))
        FileHandle.standardError.write(Data(thinking.utf8))
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private func loadSystemPromptOverride(fileManager: FileManager) throws -> String? {
        guard let systemPromptFile else { return nil }
        let path = (systemPromptFile as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: path) else {
            throw CLIError.modelNotFound(
                "System prompt file not found: \(path)",
                hint: "ultramar chat --engine qwen --system-prompt-file ./prompt.txt"
            )
        }
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CLIError.invalidFlag("System prompt file is empty: \(path)")
        }
        return text
    }

    private func prepareHarness(
        harness: InferenceChatHarness,
        install: InferenceChatHarness.InstallSnapshot,
        fileManager: FileManager
    ) async throws {
        if let modelPath {
            let url = URL(fileURLWithPath: (modelPath as NSString).expandingTildeInPath)
            guard fileManager.fileExists(atPath: url.path) else {
                throw CLIError.modelNotFound(
                    "Model file not found: \(url.path)",
                    hint: "ultramar chat --prompt \"...\" --model-path /path/to/model.gguf --engine qwen"
                )
            }
            switch engine {
            case .qwen:
                await harness.gemmaEngine.unload()
                try await harness.qwenEngine.load(modelURL: url)
            case .gemma:
                await harness.qwenEngine.unload()
                try await harness.gemmaEngine.load(modelURL: url)
            case .auto:
                throw CLIError.invalidFlag("Use --engine qwen or gemma with --model-path.")
            }
            return
        }

        switch engine {
        case .qwen:
            guard install.qwenInstalled else {
                throw CLIError.modelNotFound(
                    "Qwen model not installed.",
                    hint: "ultramar models download --engine qwen"
                )
            }
            try await harness.loadQwenBrain(fileManager: fileManager)
        case .gemma:
            guard install.gemmaInstalled else {
                throw CLIError.modelNotFound(
                    "Gemma model not installed.",
                    hint: "ultramar models download --engine gemma"
                )
            }
            try await harness.loadGemmaVision(fileManager: fileManager)
        case .auto:
            break
        }
    }
}

private typealias InstallSnapshot = InferenceChatHarness.InstallSnapshot
