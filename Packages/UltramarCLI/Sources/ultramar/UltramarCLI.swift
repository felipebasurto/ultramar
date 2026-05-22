import ArgumentParser

@main
struct UltramarCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ultramar",
        abstract: "Ultramar AI — offline travel assistant CLI for local model testing.",
        discussion: """
        Headless interface for agents and developers. Download GGUF models, run inference on macOS,
        and inspect routing without the iOS Simulator.

        Models default to ~/Library/Application Support/UltramarAI/models/ (same as the app).
        Set ULTRAMAR_MODELS_DIR or pass --models-dir to override the directory used for checks and chat paths.
        """,
        subcommands: [
            Doctor.self,
            Models.self,
            Chat.self,
            Route.self,
            FM.self,
        ],
        defaultSubcommand: nil
    )

    func run() async throws {
        print(Self.helpMessage())
    }
}
