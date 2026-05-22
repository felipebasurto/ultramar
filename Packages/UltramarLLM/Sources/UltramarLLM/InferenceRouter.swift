import UltramarCore

public enum InferenceRouter: Sendable {
    public static func route(task: AgentTask, fm: FMGateStatus) -> InferenceBackend {
        if task == .summary || task == .generable {
            fm.logSnapshot()
        }

        let backend: InferenceBackend
        switch task {
        case .toolLoop, .safety:
            backend = .edgeQwen
        case .photoAnalysis:
            backend = .edgeGemma
        case .audioAnalysis:
            backend = .edgeGemma
        case .summary where fm.isAvailable, .generable where fm.isAvailable:
            backend = .appleFoundationModels
        case .summary, .generable, .generalChat:
            backend = .edgeQwen
        }

        UltramarLog.routing.info(
            "route_decision \(UltramarLog.kv(("task", task.logLabel), ("backend", backend.logLabel), ("fm_available", fm.isAvailable)), privacy: .public)"
        )
        return backend
    }
}

public extension InferenceBackend {
    var logLabel: String {
        switch self {
        case .edgeQwen: "edgeQwen"
        case .edgeGemma: "edgeGemma"
        case .appleFoundationModels: "appleFoundationModels"
        }
    }
}
