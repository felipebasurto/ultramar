import ArgumentParser
import UltramarLLM

enum EngineOption: String, ExpressibleByArgument, CaseIterable, Sendable {
    case qwen
    case gemma
    case all

    var artifact: ModelArtifact? {
        switch self {
        case .qwen:
            ModelCatalog.qwenBrain
        case .gemma:
            ModelCatalog.gemmaVision
        case .all:
            nil
        }
    }

    static var chatChoices: [EngineOption] { [.qwen, .gemma] }

    enum ChatEngine: String, ExpressibleByArgument, CaseIterable, Sendable {
        case qwen
        case gemma
        case auto
    }
}
