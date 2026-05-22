import UltramarCore

public struct ProviderSelectionContext: Sendable, Equatable {
    public let task: AgentTask
    public let backend: InferenceBackend
    public let fm: FMGateStatus
    public let qwenInstalled: Bool
    public let qwenLoaded: Bool
    public let gemmaInstalled: Bool
    public let gemmaLoaded: Bool

    public init(
        task: AgentTask,
        backend: InferenceBackend,
        fm: FMGateStatus,
        qwenInstalled: Bool,
        qwenLoaded: Bool,
        gemmaInstalled: Bool,
        gemmaLoaded: Bool
    ) {
        self.task = task
        self.backend = backend
        self.fm = fm
        self.qwenInstalled = qwenInstalled
        self.qwenLoaded = qwenLoaded
        self.gemmaInstalled = gemmaInstalled
        self.gemmaLoaded = gemmaLoaded
    }
}
