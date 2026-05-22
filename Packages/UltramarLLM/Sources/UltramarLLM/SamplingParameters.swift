import Foundation

public enum QwenReasoningMode: String, Sendable, Equatable {
    case finalOnly
    case thinking

    var switchToken: String {
        switch self {
        case .finalOnly:
            return "/no_think"
        case .thinking:
            return "/think"
        }
    }
}

public struct SamplingParameters: Sendable, Equatable {
    public let temperature: Float
    public let topP: Float
    public let topK: Int32
    public let minP: Float
    public let presencePenalty: Float
    public let repeatPenalty: Float
    public let frequencyPenalty: Float
    public let penaltyLastN: Int32
    public let seed: UInt32

    public init(
        temperature: Float,
        topP: Float,
        topK: Int32,
        minP: Float,
        presencePenalty: Float,
        repeatPenalty: Float,
        frequencyPenalty: Float = 0,
        penaltyLastN: Int32 = 64,
        seed: UInt32 = UInt32.max
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.presencePenalty = presencePenalty
        self.repeatPenalty = repeatPenalty
        self.frequencyPenalty = frequencyPenalty
        self.penaltyLastN = penaltyLastN
        self.seed = seed
    }
}

public enum SamplingPreset {
    public static let qwenFinalOnly = SamplingParameters(
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
        minP: 0,
        presencePenalty: 1.5,
        repeatPenalty: 1.0
    )

    public static let qwenThinking = SamplingParameters(
        temperature: 1.0,
        topP: 0.95,
        topK: 20,
        minP: 0,
        presencePenalty: 1.5,
        repeatPenalty: 1.0
    )

    public static func qwen(_ mode: QwenReasoningMode) -> SamplingParameters {
        switch mode {
        case .finalOnly:
            return qwenFinalOnly
        case .thinking:
            return qwenThinking
        }
    }
}
