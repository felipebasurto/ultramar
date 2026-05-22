public enum EngineRole: String, CaseIterable, Sendable, Equatable {
    case qwenBrain = "qwen"
    case gemmaVision = "gemma"
    case none

    public var displayName: String {
        switch self {
        case .qwenBrain:
            "Qwen 3.5"
        case .gemmaVision:
            "Gemma 4"
        case .none:
            "None"
        }
    }
}
