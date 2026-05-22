import Foundation
import UltramarCore

public enum ModelManifestStoreError: Error, LocalizedError {
    case encodeFailed
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case .encodeFailed:
            "Could not save model manifest."
        case .decodeFailed:
            "Could not read model manifest."
        }
    }
}

public struct ModelReconcileContext: Sendable, Equatable {
    public var hasActiveDownload: Bool
    public var hasResumeData: Bool

    public init(hasActiveDownload: Bool, hasResumeData: Bool) {
        self.hasActiveDownload = hasActiveDownload
        self.hasResumeData = hasResumeData
    }

    public static let none = ModelReconcileContext(hasActiveDownload: false, hasResumeData: false)
}

public struct ModelManifestStore {
    private let fileManager: FileManager
    private let manifestURL: URL

    public init(fileManager: FileManager = .default, manifestURL: URL? = nil) {
        self.fileManager = fileManager
        self.manifestURL = manifestURL ?? ModelPaths.manifestURL(fileManager: fileManager)
    }

    public func load() throws -> ModelManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ModelManifest()
        }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ModelManifest.self, from: data) else {
            throw ModelManifestStoreError.decodeFailed
        }
        return manifest
    }

    public func save(_ manifest: ModelManifest) throws {
        _ = try ModelPaths.modelsDirectory(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else {
            UltramarLog.models.error("manifest_save_failed error=encodeFailed")
            throw ModelManifestStoreError.encodeFailed
        }
        let temporaryURL = manifestURL.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: manifestURL)
    }

    public func reconcile(
        artifact: ModelArtifact,
        verifier: ModelIntegrityVerifier = ModelIntegrityVerifier(),
        context: ModelReconcileContext = .none
    ) throws -> ModelManifest {
        var manifest = try load()
        let localURL = ModelCatalog.localURL(for: artifact, fileManager: fileManager)
        let fileExists = fileManager.fileExists(atPath: localURL.path)
        let previousState = manifest[artifact.id]?.state

        switch manifest[artifact.id]?.state {
        case .installed?:
            if !fileExists {
                manifest[artifact.id] = ModelManifestEntry(
                    artifactID: artifact.id,
                    state: .notInstalled
                )
            }
        case .downloading?, .verifying?:
            if fileExists, verifier.passesSizeCheck(fileURL: localURL, artifact: artifact) {
                let bytes = try fileByteCount(at: localURL)
                let digest = (try? verifier.sha256Hex(of: localURL)) ?? ""
                manifest[artifact.id] = ModelManifestEntry(
                    artifactID: artifact.id,
                    state: .installed(installedAt: .now, bytesOnDisk: bytes, sha256: digest)
                )
            } else if !fileExists, !context.hasActiveDownload, context.hasResumeData {
                manifest[artifact.id] = ModelManifestEntry(
                    artifactID: artifact.id,
                    state: .paused
                )
            }
        default:
            if fileExists, verifier.passesSizeCheck(fileURL: localURL, artifact: artifact) {
                let bytes = try fileByteCount(at: localURL)
                let digest = (try? verifier.sha256Hex(of: localURL)) ?? ""
                manifest[artifact.id] = ModelManifestEntry(
                    artifactID: artifact.id,
                    state: .installed(installedAt: .now, bytesOnDisk: bytes, sha256: digest)
                )
            } else if manifest[artifact.id] == nil {
                manifest[artifact.id] = ModelManifestEntry(
                    artifactID: artifact.id,
                    state: .notInstalled
                )
            }
        }

        let newState = manifest[artifact.id]?.state ?? .notInstalled
        if previousState != newState || previousState == nil {
            UltramarLog.models.info(
                "manifest_reconcile \(UltramarLog.kv(("artifact", artifact.id), ("previous_state", previousState?.logLabel ?? "none"), ("new_state", newState.logLabel), ("file_exists", fileExists)), privacy: .public)"
            )
        }

        try save(manifest)
        return manifest
    }

    private func fileByteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
