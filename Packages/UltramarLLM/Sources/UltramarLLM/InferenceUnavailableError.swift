import Foundation

public enum InferenceUnavailableError: Error, LocalizedError, Equatable {
    case qwenRequired
    case qwenNotLoaded
    case gemmaRequired
    case gemmaNotLoaded
    case noBackendAvailable

    public var errorDescription: String? {
        switch self {
        case .qwenRequired:
            "Download the Qwen brain model to use this feature."
        case .qwenNotLoaded:
            "Load the Qwen brain model before chatting."
        case .gemmaRequired:
            "Download the Gemma vision model for photo and audio tasks."
        case .gemmaNotLoaded:
            "Load the Gemma vision model before analyzing media."
        case .noBackendAvailable:
            "No AI engine is available. Download Qwen or enable Apple Intelligence."
        }
    }
}
