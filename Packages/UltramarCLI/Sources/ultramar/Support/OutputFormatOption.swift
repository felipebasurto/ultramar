import ArgumentParser
import Foundation

enum OutputFormatOption: String, ExpressibleByArgument, CaseIterable, Sendable {
    case text
    case json

    var isJSON: Bool { self == .json }
}

struct GlobalOptions: ParsableArguments {
    @Option(
        name: .long,
        help: "Output format: text (human) or json (agents)."
    )
    var format: OutputFormatOption = .text

    @Option(
        name: .long,
        help: "Models directory (default: Application Support/UltramarAI/models). Overrides ULTRAMAR_MODELS_DIR when set."
    )
    var modelsDir: String?

    func resolvedModelsDirectory(fileManager: FileManager = .default) throws -> URL {
        try CLIPaths.modelsDirectory(override: modelsDir, fileManager: fileManager)
    }
}
