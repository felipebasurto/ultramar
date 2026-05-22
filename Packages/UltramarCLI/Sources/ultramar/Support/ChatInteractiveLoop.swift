import Darwin
import Foundation
import UltramarCore
import UltramarLLM

enum ChatInteractiveLoop {
    static var stdinIsTTY: Bool {
        isatty(STDIN_FILENO) != 0
    }

    static func shouldRun(interactiveFlag: Bool, hasPromptSources: Bool) -> Bool {
        guard !hasPromptSources else { return false }
        return interactiveFlag || stdinIsTTY
    }

    static func isExitCommand(_ line: String) -> Bool {
        switch line.lowercased() {
        case "/exit", "/quit", "/q", "exit", "quit":
            true
        default:
            false
        }
    }

    static func printBanner(to handle: FileHandle = .standardError) {
        handle.write(
            Data(
                """
                Ultramar — asistente de viaje offline
                /help  /new  /system <file>  /system reset  /exit
                Cargando modelo…

                """.utf8
            )
        )
    }

    static func printHelp(to handle: FileHandle = .standardError) {
        handle.write(
            Data(
                """
                Escribe tu pregunta de viaje y pulsa Enter.
                /new — nueva conversación
                /system <file> — cargar system prompt UTF-8 y limpiar conversación
                /system reset — volver al system prompt default y limpiar conversación
                /exit — salir   /help — ayuda

                """.utf8
            )
        )
    }

    static func systemPromptPath(from line: String) -> String? {
        let prefix = "/system "
        guard line.hasPrefix(prefix) else { return nil }
        let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.lowercased() != "reset" else { return nil }
        return value
    }

    static func isSystemResetCommand(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/system reset"
    }

    static func loadSystemPrompt(path rawPath: String, fileManager: FileManager = .default) throws -> String {
        let path = (rawPath as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: path) else {
            throw CLIError.modelNotFound(
                "System prompt file not found: \(path)",
                hint: "/system ./prompt.txt"
            )
        }
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CLIError.invalidFlag("System prompt file is empty: \(path)")
        }
        return text
    }

    static func run(
        harness: InferenceChatHarness,
        session: inout ChatSession,
        profile: ProductChatProfile,
        install: InferenceChatHarness.InstallSnapshot,
        showThinkingInOutput: Bool,
        progress: Bool,
        verbose: Bool,
        fileManager: FileManager
    ) async throws -> Int {
        var turnNumber = 0
        var currentProfile = profile
        while true {
            FileHandle.standardError.write(Data("> ".utf8))
            guard let line = readLine() else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if isExitCommand(trimmed) { break }
            if trimmed == "/help" {
                printHelp()
                continue
            }
            if trimmed == "/new" {
                session.clear()
                FileHandle.standardError.write(Data("Conversación reiniciada.\n".utf8))
                continue
            }
            if isSystemResetCommand(trimmed) {
                currentProfile.presentation.systemPromptOverride = nil
                session.clear()
                FileHandle.standardError.write(Data("System prompt default restaurado. Conversación reiniciada.\n".utf8))
                continue
            }
            if let promptPath = systemPromptPath(from: trimmed) {
                currentProfile.presentation.systemPromptOverride = try loadSystemPrompt(
                    path: promptPath,
                    fileManager: fileManager
                )
                session.clear()
                FileHandle.standardError.write(Data("System prompt cargado. Conversación reiniciada.\n".utf8))
                continue
            }

            turnNumber += 1
            if progress {
                FileHandle.standardError.write(Data("Prompt \(turnNumber) (\(trimmed.count) chars)…\n".utf8))
            }

            let progressReporter = CLIProgressReporter(enabled: progress)
            let onTokenProgress: (@Sendable (Int) -> Void)? = progress
                ? { @Sendable count in progressReporter.report(tokens: count) }
                : nil

            let streamState = StreamOutputState(enabled: currentProfile.streamingEnabled, includeSeparator: false)
            let onPartialAnswer: (@Sendable (String) -> Void)? = currentProfile.streamingEnabled
                ? { @Sendable delta in streamState.write(delta) }
                : nil

            var activeProfile = currentProfile
            activeProfile.presentation = ChatPresentation(
                showThinking: showThinkingInOutput,
                qwenReasoningMode: currentProfile.presentation.qwenReasoningMode,
                systemPromptOverride: currentProfile.presentation.systemPromptOverride
            )

            let inferenceStart = ContinuousClock.now
            let sendResult: InferenceChatHarness.SendResult
            do {
                sendResult = try await harness.sendInSession(
                    prompt: trimmed,
                    session: &session,
                    profile: activeProfile,
                    install: install,
                    onTokenProgress: onTokenProgress,
                    onPartialAnswer: onPartialAnswer,
                    fileManager: fileManager
                )
            } catch {
                progressReporter.finish()
                FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
                continue
            }
            progressReporter.finish()

            let inferenceMs = LogTimer.durationMilliseconds(since: inferenceStart)
            let timing = CLITimingSummary(
                engine: sendResult.providerLabel,
                loadDurationMs: 0,
                inferenceDurationMs: inferenceMs,
                tokensGenerated: sendResult.tokensGenerated
            )

            if currentProfile.streamingEnabled {
                streamState.finish(fallbackAnswer: sendResult.answer)
            } else {
                let display = sendResult.displayText(showThinking: showThinkingInOutput)
                let answer = display.isEmpty ? "No response generated." : display
                Swift.print(answer)
            }
            Swift.print("")
            if verbose {
                CLITimingSummary.writeStderrLine(timing)
            }

            if verbose, showThinkingInOutput,
               let thinking = sendResult.thinking, !thinking.isEmpty
            {
                FileHandle.standardError.write(Data("--- Thinking ---\n".utf8))
                FileHandle.standardError.write(Data(thinking.utf8))
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }
        return turnNumber
    }

    static func run(
        orchestrator: ChatOrchestrator,
        messages: inout [ChatMessage],
        systemPrompt: inout String?,
        reasoningMode: QwenReasoningMode,
        showThinkingInOutput: Bool,
        progress: Bool,
        verbose: Bool,
        fileManager: FileManager
    ) async throws -> Int {
        var turnNumber = 0
        while true {
            FileHandle.standardError.write(Data("> ".utf8))
            guard let line = readLine() else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if isExitCommand(trimmed) { break }
            if trimmed == "/help" {
                printHelp()
                continue
            }
            if trimmed == "/new" {
                messages.removeAll()
                orchestrator.resetSession()
                FileHandle.standardError.write(Data("Conversación reiniciada.\n".utf8))
                continue
            }
            if isSystemResetCommand(trimmed) {
                systemPrompt = nil
                messages.removeAll()
                orchestrator.resetSession()
                FileHandle.standardError.write(Data("System prompt default restaurado. Conversación reiniciada.\n".utf8))
                continue
            }
            if let promptPath = systemPromptPath(from: trimmed) {
                systemPrompt = try loadSystemPrompt(
                    path: promptPath,
                    fileManager: fileManager
                )
                messages.removeAll()
                orchestrator.resetSession()
                FileHandle.standardError.write(Data("System prompt cargado. Conversación reiniciada.\n".utf8))
                continue
            }

            turnNumber += 1
            if progress {
                FileHandle.standardError.write(Data("Prompt \(turnNumber) (\(trimmed.count) chars)…\n".utf8))
            }

            let userMessage = ChatMessage(role: .user, content: trimmed)
            let request = ChatRequest(
                messages: messages + [userMessage],
                systemPrompt: systemPrompt,
                reasoningMode: reasoningMode,
                maxTokens: reasoningMode == .thinking ? 1536 : 512,
                showThinking: showThinkingInOutput
            )

            let response: ChatResponse
            do {
                response = try await orchestrator.send(request)
            } catch {
                FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
                continue
            }

            messages.append(userMessage)
            messages.append(ChatMessage(role: .assistant, content: response.answer))

            let display = response.displayText(showThinking: showThinkingInOutput)
            Swift.print(display.isEmpty ? "No response generated." : display)
            Swift.print("")

            if verbose {
                CLITimingSummary.writeStderrLine(
                    CLITimingSummary(
                        engine: response.providerLabel,
                        loadDurationMs: 0,
                        inferenceDurationMs: response.durationMs,
                        tokensGenerated: response.tokens
                    )
                )
            }
            if verbose, showThinkingInOutput,
               let thinking = response.hiddenReasoning, !thinking.isEmpty
            {
                FileHandle.standardError.write(Data("--- Thinking ---\n".utf8))
                FileHandle.standardError.write(Data(thinking.utf8))
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }
        return turnNumber
    }
}
