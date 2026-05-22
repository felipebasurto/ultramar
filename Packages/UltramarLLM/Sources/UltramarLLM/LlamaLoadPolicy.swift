import Foundation

enum LlamaLoadPolicy {
    static let contextTokens = 4096

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var gpuLayerCount: Int32 {
        isSimulator ? 0 : -1
    }

    /// Simulator runs Qwen on CPU only (no Metal offload); keep budgets small for dev UX.
    static var maxGenerationTokens: Int {
        maxGenerationTokens(reasoningMode: .thinking)
    }

    static func maxGenerationTokens(reasoningMode: QwenReasoningMode) -> Int {
        if isSimulator {
            return 96
        }
        switch reasoningMode {
        case .finalOnly:
            return 512
        case .thinking:
            return 1536
        }
    }
}
