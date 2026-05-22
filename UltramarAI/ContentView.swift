import SwiftUI
import UltramarCore
import UltramarLLM

struct ContentView: View {
    @State private var userPrompt: String = ""
    @State private var chatSession = ChatSession()
    @State private var streamingAssistantText: String = ""
    @State private var lastThinking: String = ""
    @State private var showThinking = false
    @State private var errorMessage: String?
    @State private var modelStore = ModelStore()
    @State private var chatHarness = InferenceChatHarness()
    @State private var isLoadingQwen = false
    @State private var isLoadingGemma = false
    @State private var isGenerating = false
    @State private var generatingTokenCount = 0

    private var canSend: Bool {
        !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
            && chatHarness.qwenEngine.isLoaded
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Chat") {
                    if chatSession.isEmpty, streamingAssistantText.isEmpty {
                        Text("Load Qwen, then ask about travel, safety, or local tips.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(chatSession.turns) { turn in
                        chatBubble(for: turn)
                    }

                    if isGenerating, !streamingAssistantText.isEmpty {
                        chatBubble(
                            for: ChatTurn(role: .assistant, content: streamingAssistantText),
                            isStreaming: true
                        )
                    }

                    TextField("Ask about travel, safety, or local tips", text: $userPrompt, axis: .vertical)
                        .lineLimit(3...6)

                    Toggle("Show model thinking", isOn: $showThinking)

                    HStack {
                        Button("Send") {
                            sendPrompt()
                        }
                        .disabled(!canSend)

                        Button("Clear chat") {
                            clearChat()
                        }
                        .disabled(chatSession.isEmpty && streamingAssistantText.isEmpty)
                    }

                    if !chatHarness.qwenEngine.isLoaded {
                        Text("Load Qwen before sending messages.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if isGenerating {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView()
                                if generatingTokenCount > 0 {
                                    Text("Generating… \(generatingTokenCount) tokens")
                                } else {
                                    Text("Generating…")
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            #if targetEnvironment(simulator)
                            Text(
                                "Simulator uses CPU-only inference and is much slower than a physical device. "
                                    + "For realistic speed, run on hardware."
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            #endif
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if showThinking, !lastThinking.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Thinking")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lastThinking)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Downloads") {
                    Toggle("Allow download on cellular", isOn: $modelStore.allowsCellularDownloads)
                }

                Section("Qwen 3.5") {
                    modelSection(
                        statusLabel: modelStatusLabel(modelStore.qwenState),
                        bytesLabel: modelStore.downloadBytesLabel,
                        progress: modelStore.downloadProgress,
                        isVerifying: {
                            if case .verifying = modelStore.qwenState { return true }
                            return false
                        }(),
                        isLoaded: chatHarness.qwenEngine.isLoaded,
                        isLoading: isLoadingQwen,
                        loadLabel: "Load Qwen",
                        canLoad: modelStore.isModelInstalled && !chatHarness.qwenEngine.isLoaded && !isLoadingQwen,
                        onLoad: { Task { await loadQwenEngine() } },
                        actions: { qwenModelActions }
                    )
                }

                Section("Gemma 4") {
                    modelSection(
                        statusLabel: modelStatusLabel(modelStore.gemmaState),
                        bytesLabel: modelStore.gemmaDownloadBytesLabel,
                        progress: modelStore.gemmaDownloadProgress,
                        isVerifying: {
                            if case .verifying = modelStore.gemmaState { return true }
                            return false
                        }(),
                        isLoaded: chatHarness.gemmaEngine.isLoaded,
                        isLoading: isLoadingGemma,
                        loadLabel: "Load Gemma",
                        canLoad: modelStore.isGemmaInstalled && !chatHarness.gemmaEngine.isLoaded && !isLoadingGemma,
                        onLoad: { Task { await loadGemmaEngine() } },
                        actions: { gemmaModelActions }
                    )
                }

                if let installError = modelStore.installError {
                    Section {
                        Text(installError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(AppInfo.displayName)
            .onAppear {
                UltramarLog.app.info("app_launch version=\(AppInfo.version)")
                let fmGate = FMGateDetector.current()
                fmGate.logSnapshot()
                modelStore.refreshInstallationStatus()
            }
        }
    }

    @ViewBuilder
    private func modelSection<A: View>(
        statusLabel: String,
        bytesLabel: String?,
        progress: Double?,
        isVerifying: Bool,
        isLoaded: Bool,
        isLoading: Bool,
        loadLabel: String,
        canLoad: Bool,
        onLoad: @escaping () -> Void,
        @ViewBuilder actions: () -> A
    ) -> some View {
        LabeledContent("Status", value: statusLabel)
        LabeledContent("Engine", value: isLoaded ? "Loaded" : "Not loaded")

        actions()

        if let bytesLabel {
            Text(bytesLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let progress {
            ProgressView(value: progress)
        }

        if isVerifying {
            HStack {
                ProgressView()
                Text("Verifying download…")
            }
        }

        Button(action: onLoad) {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading…")
                }
            } else {
                Text(loadLabel)
            }
        }
        .disabled(!canLoad)
    }

    @ViewBuilder
    private var qwenModelActions: some View {
        switch modelStore.qwenState {
        case .notInstalled:
            Button("Download") {
                Task { await startQwenDownload() }
            }
        case .downloading:
            Button("Cancel download", role: .destructive) {
                Task { await cancelQwenDownload() }
            }
        case .paused:
            Button("Resume download") {
                Task { await resumeQwenDownload() }
            }
            Button("Delete partial download", role: .destructive) {
                Task { await deletePartialQwenDownload() }
            }
        case .verifying:
            EmptyView()
        case .installed:
            Button("Remove model", role: .destructive) {
                Task { await removeQwenModel() }
            }
        case .failed:
            Button("Retry download") {
                Task { await startQwenDownload() }
            }
            Button("Delete partial download", role: .destructive) {
                Task { await deletePartialQwenDownload() }
            }
        }
    }

    @ViewBuilder
    private var gemmaModelActions: some View {
        switch modelStore.gemmaState {
        case .notInstalled:
            Button("Download") {
                Task { await startGemmaDownload() }
            }
        case .downloading:
            Button("Cancel download", role: .destructive) {
                Task { await cancelGemmaDownload() }
            }
        case .paused:
            Button("Resume download") {
                Task { await resumeGemmaDownload() }
            }
            Button("Delete partial download", role: .destructive) {
                Task { await deletePartialGemmaDownload() }
            }
        case .verifying:
            EmptyView()
        case .installed:
            Button("Remove model", role: .destructive) {
                Task { await removeGemmaModel() }
            }
        case .failed:
            Button("Retry download") {
                Task { await startGemmaDownload() }
            }
            Button("Delete partial download", role: .destructive) {
                Task { await deletePartialGemmaDownload() }
            }
        }
    }

    private func modelStatusLabel(_ state: ModelInstallState) -> String {
        switch state {
        case .notInstalled:
            return "Not installed"
        case .downloading:
            return "Downloading…"
        case .paused:
            return "Paused"
        case .verifying:
            return "Verifying…"
        case .installed:
            return "Installed"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }

    private func startQwenDownload() async {
        await performModelAction {
            try await modelStore.downloadQwenBrain()
        }
    }

    private func cancelQwenDownload() async {
        await performModelAction {
            try await modelStore.cancelQwenDownload()
        }
    }

    private func resumeQwenDownload() async {
        await performModelAction {
            try await modelStore.resumeQwenDownload()
        }
    }

    private func deletePartialQwenDownload() async {
        await performModelAction {
            try await modelStore.deletePartialQwenDownload()
        }
    }

    private func removeQwenModel() async {
        await performModelAction {
            await chatHarness.qwenEngine.unload()
            try modelStore.removeQwenModel()
        }
    }

    private func startGemmaDownload() async {
        await performModelAction {
            try await modelStore.downloadGemmaVision()
        }
    }

    private func cancelGemmaDownload() async {
        await performModelAction {
            try await modelStore.cancelGemmaDownload()
        }
    }

    private func resumeGemmaDownload() async {
        await performModelAction {
            try await modelStore.resumeGemmaDownload()
        }
    }

    private func deletePartialGemmaDownload() async {
        await performModelAction {
            try await modelStore.deletePartialGemmaDownload()
        }
    }

    private func removeGemmaModel() async {
        await performModelAction {
            await chatHarness.gemmaEngine.unload()
            try modelStore.removeGemmaModel()
        }
    }

    private func performModelAction(_ action: () async throws -> Void) async {
        errorMessage = nil
        modelStore.installError = nil
        do {
            try await action()
        } catch {
            modelStore.installError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func loadQwenEngine() async {
        isLoadingQwen = true
        errorMessage = nil
        defer { isLoadingQwen = false }

        do {
            try await chatHarness.loadQwenBrain()
        } catch {
            UltramarLog.app.error(
                "engine_load_failed \(UltramarLog.kv(("engine", "qwen"), ("error", error.localizedDescription)), privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    private func loadGemmaEngine() async {
        isLoadingGemma = true
        errorMessage = nil
        defer { isLoadingGemma = false }

        do {
            try await chatHarness.loadGemmaVision()
        } catch {
            UltramarLog.app.error(
                "engine_load_failed \(UltramarLog.kv(("engine", "gemma"), ("error", error.localizedDescription)), privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func chatBubble(for turn: ChatTurn, isStreaming: Bool = false) -> some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
            Text(turn.role == .user ? "You" : "Ultramar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.content)
                .font(.body)
                .foregroundStyle(turn.role == .user ? .primary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
            if isStreaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func clearChat() {
        chatSession.clear()
        streamingAssistantText = ""
        lastThinking = ""
        errorMessage = nil
    }

    private func sendPrompt() {
        guard canSend else { return }

        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        isGenerating = true
        generatingTokenCount = 0
        streamingAssistantText = ""
        lastThinking = ""
        userPrompt = ""

        Task { @MainActor in
            defer { isGenerating = false }
            errorMessage = nil
            do {
                let install = InferenceChatHarness.InstallSnapshot(
                    qwenInstalled: modelStore.isModelInstalled,
                    gemmaInstalled: modelStore.isGemmaInstalled
                )
                var profile = ProductChatProfile.standard
                profile.presentation.showThinking = showThinking
                profile.presentation.qwenReasoningMode = showThinking ? .thinking : .finalOnly

                var session = chatSession
                let result = try await chatHarness.sendInSession(
                    prompt: prompt,
                    session: &session,
                    profile: profile,
                    install: install,
                    onTokenProgress: { count in
                        Task { @MainActor in
                            generatingTokenCount = count
                        }
                    },
                    onPartialAnswer: { delta in
                        Task { @MainActor in
                            streamingAssistantText += delta
                        }
                    }
                )
                chatSession = session
                streamingAssistantText = ""
                if showThinking, let thinking = result.thinking, !thinking.isEmpty {
                    lastThinking = thinking
                }
            } catch {
                UltramarLog.app.error(
                    "chat_error \(UltramarLog.kv(("error", error.localizedDescription)), privacy: .public)"
                )
                errorMessage = error.localizedDescription
                streamingAssistantText = ""
            }
        }
    }
}

#Preview {
    ContentView()
}
