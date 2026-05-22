import Foundation

public extension ModelInstallState {
    /// Whether a manifest transition should emit `manifest_state_changed` (skips download byte ticks).
    func shouldLogManifestTransition(from previous: ModelInstallState?) -> Bool {
        switch (previous, self) {
        case let (.downloading(_, prevExpected), .downloading(_, newExpected))
            where prevExpected == newExpected:
            false
        default:
            previous != self
        }
    }

    var logLabel: String {
        switch self {
        case .notInstalled:
            "notInstalled"
        case let .downloading(bytesWritten, bytesExpected):
            "downloading(\(bytesWritten)/\(bytesExpected))"
        case .paused:
            "paused"
        case .verifying:
            "verifying"
        case let .installed(_, bytesOnDisk, _):
            "installed(\(bytesOnDisk))"
        case let .failed(message):
            "failed(\(message.prefix(40)))"
        }
    }
}
