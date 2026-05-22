import ArgumentParser
import UltramarLLM

struct Route: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "route",
        abstract: "Inspect inference routing without loading models.",
        usage: """
        Examples:
          ultramar route --task toolLoop --format json
          ultramar route --task summary --fm-available
          ultramar route --task generalChat --qwen-installed --qwen-loaded
        """
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Agent task to route.")
    var task: AgentTaskOption = .generalChat

    @Flag(name: .long, help: "Simulate FM gate as available (all gates on).")
    var fmAvailable: Bool = false

    @Flag(name: .long, help: "Simulate FM user toggle off.")
    var fmUserToggleOff: Bool = false

    @Flag(name: .long, help: "Qwen GGUF installed on disk.")
    var qwenInstalled: Bool = false

    @Flag(name: .long, help: "Qwen engine loaded in memory.")
    var qwenLoaded: Bool = false

    @Flag(name: .long, help: "Gemma GGUF installed on disk.")
    var gemmaInstalled: Bool = false

    @Flag(name: .long, help: "Gemma engine loaded in memory.")
    var gemmaLoaded: Bool = false

    func run() throws {
        let fm: FMGateStatus
        if fmUserToggleOff {
            fm = .userToggleOff
        } else if fmAvailable {
            fm = .allEnabled
        } else {
            fm = FMGateDetector.current()
        }

        let agentTask = task.task
        let backend = InferenceRouter.route(task: agentTask, fm: fm)

        let context = ProviderSelectionContext(
            task: agentTask,
            backend: backend,
            fm: fm,
            qwenInstalled: qwenInstalled,
            qwenLoaded: qwenLoaded,
            gemmaInstalled: gemmaInstalled,
            gemmaLoaded: gemmaLoaded
        )

        let providerSelection: String
        do {
            let provider = try LLMProviderFactory.makeProvider(
                context: context,
                qwenEngine: Qwen35Engine(),
                gemmaEngine: Gemma4Engine(),
                fmProvider: FoundationModelsProvider()
            )
            providerSelection = providerLogLabel(provider)
        } catch {
            providerSelection = "error:\(error.localizedDescription)"
        }

        CLIOutput.print(
            [
                "ok": .bool(true),
                "task": .string(agentTask.logLabel),
                "backend": .string(backend.logLabel),
                "fm_available": .bool(fm.isAvailable),
                "provider": .string(providerSelection),
                "allows_fm_fallback": .bool(LLMProviderFactory.allowsFMFallback(for: agentTask)),
            ],
            format: global.format
        )
    }

    private func providerLogLabel(_ provider: any LLMProvider) -> String {
        if provider is Qwen35Engine { return "qwen" }
        if provider is Gemma4Engine { return "gemma" }
        if provider is FoundationModelsProvider { return "appleFM" }
        return "unknown"
    }
}
