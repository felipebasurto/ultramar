import Foundation

public enum ModelInstallState: Codable, Equatable, Sendable {
    case notInstalled
    case downloading(bytesWritten: Int64, bytesExpected: Int64)
    case paused
    case verifying
    case installed(installedAt: Date, bytesOnDisk: Int64, sha256: String)
    case failed(message: String)

    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    public var progressFraction: Double? {
        switch self {
        case let .downloading(bytesWritten, bytesExpected):
            guard bytesExpected > 0 else { return nil }
            return min(max(Double(bytesWritten) / Double(bytesExpected), 0), 1)
        case .verifying:
            return nil
        default:
            return nil
        }
    }
}

public struct ModelManifestEntry: Codable, Equatable, Sendable {
    public var artifactID: String
    public var state: ModelInstallState
    public var updatedAt: Date

    public init(artifactID: String, state: ModelInstallState, updatedAt: Date = .now) {
        self.artifactID = artifactID
        self.state = state
        self.updatedAt = updatedAt
    }
}

public struct ModelManifest: Codable, Equatable, Sendable {
    public var entries: [String: ModelManifestEntry]

    public init(entries: [String: ModelManifestEntry] = [:]) {
        self.entries = entries
    }

    public subscript(artifactID: String) -> ModelManifestEntry? {
        get { entries[artifactID] }
        set {
            if let newValue {
                entries[artifactID] = newValue
            } else {
                entries.removeValue(forKey: artifactID)
            }
        }
    }
}
