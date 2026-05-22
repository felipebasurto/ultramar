import ArgumentParser
import UltramarLLM

enum AgentTaskOption: String, ExpressibleByArgument, CaseIterable, Sendable {
    case toolLoop
    case safety
    case photoAnalysis
    case audioAnalysis
    case summary
    case generable
    case generalChat

    var task: AgentTask {
        switch self {
        case .toolLoop: .toolLoop
        case .safety: .safety
        case .photoAnalysis: .photoAnalysis
        case .audioAnalysis: .audioAnalysis
        case .summary: .summary
        case .generable: .generable
        case .generalChat: .generalChat
        }
    }
}
