import Foundation
import Observation
import UltramarCore

public enum ModelStoreError: Error, LocalizedError {
    case downloadFailed(String)
    case moveFailed(String)
    case importFailed(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case cellularNotAllowed

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            "Model download failed: \(message)"
        case .moveFailed(let message):
            "Could not install model: \(message)"
        case .importFailed(let message):
            "Could not import model: \(message)"
        case let .insufficientDiskSpace(required, available):
            "Not enough storage. Need \(Self.formatGB(required)), have \(Self.formatGB(available))."
        case .cellularNotAllowed:
            NetworkPolicyError.cellularNotAllowed.localizedDescription
        }
    }

    private static func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

@MainActor
@Observable
public final class ModelStore {
    public private(set) var qwenState: ModelInstallState = .notInstalled
    public private(set) var gemmaState: ModelInstallState = .notInstalled
    public var installError: String?

    public var allowsCellularDownloads: Bool {
        get { UserDefaults.standard.bool(forKey: Self.cellularDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.cellularDefaultsKey) }
    }

    public var isModelInstalled: Bool { qwenState.isInstalled }
    public var isGemmaInstalled: Bool { gemmaState.isInstalled }

    public var downloadProgress: Double? { qwenState.progressFraction }
    public var gemmaDownloadProgress: Double? { gemmaState.progressFraction }

    public var downloadBytesLabel: String? {
        bytesLabel(for: qwenState)
    }

    public var gemmaDownloadBytesLabel: String? {
        bytesLabel(for: gemmaState)
    }

    private static let cellularDefaultsKey = "UltramarAI.allowsCellularModelDownloads"

    private let fileManager: FileManager
    private let downloadService: ModelDownloadService

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.downloadService = ModelDownloadService(fileManager: fileManager)
        self.downloadService.onStateChanged = { [weak self] in
            self?.refreshStateFromManifest()
        }
        Task { await self.refreshInstallationFromBootstrap() }
    }

    package init(fileManager: FileManager, downloadService: ModelDownloadService) {
        self.fileManager = fileManager
        self.downloadService = downloadService
        self.downloadService.onStateChanged = { [weak self] in
            self?.refreshStateFromManifest()
        }
        Task { await self.refreshInstallationFromBootstrap() }
    }

    public func refreshInstallationStatus() {
        Task { await refreshInstallationFromBootstrap() }
    }

    public func downloadQwenBrain() async throws {
        installError = nil
        UltramarLog.models.info("user_download artifact=qwen-brain")
        try await download(artifact: ModelCatalog.qwenBrain)
    }

    public func downloadGemmaVision() async throws {
        installError = nil
        UltramarLog.models.info("user_download artifact=gemma-vision")
        try await download(artifact: ModelCatalog.gemmaVision)
    }

    public func cancelQwenDownload() async throws {
        installError = nil
        UltramarLog.models.info("user_cancel artifact=qwen-brain")
        try await downloadService.cancel(artifact: ModelCatalog.qwenBrain)
        refreshStateFromManifest()
    }

    public func cancelGemmaDownload() async throws {
        installError = nil
        UltramarLog.models.info("user_cancel artifact=gemma-vision")
        try await downloadService.cancel(artifact: ModelCatalog.gemmaVision)
        refreshStateFromManifest()
    }

    public func resumeQwenDownload() async throws {
        installError = nil
        UltramarLog.models.info("user_resume artifact=qwen-brain")
        try await resume(artifact: ModelCatalog.qwenBrain)
    }

    public func resumeGemmaDownload() async throws {
        installError = nil
        UltramarLog.models.info("user_resume artifact=gemma-vision")
        try await resume(artifact: ModelCatalog.gemmaVision)
    }

    public func removeQwenModel() throws {
        installError = nil
        UltramarLog.models.info("user_remove artifact=qwen-brain")
        try downloadService.remove(artifact: ModelCatalog.qwenBrain)
        refreshStateFromManifest()
    }

    public func removeGemmaModel() throws {
        installError = nil
        UltramarLog.models.info("user_remove artifact=gemma-vision")
        try downloadService.remove(artifact: ModelCatalog.gemmaVision)
        refreshStateFromManifest()
    }

    public func deletePartialQwenDownload() async throws {
        installError = nil
        try await downloadService.deletePartial(artifact: ModelCatalog.qwenBrain)
        refreshStateFromManifest()
    }

    public func deletePartialGemmaDownload() async throws {
        installError = nil
        try await downloadService.deletePartial(artifact: ModelCatalog.gemmaVision)
        refreshStateFromManifest()
    }

    /// Legacy API — forwards to `downloadQwenBrain()`.
    public func installModel(from url: URL = ModelPaths.huggingFaceDownloadURL) async throws {
        _ = url
        try await downloadQwenBrain()
    }

    public func importModel(from sourceURL: URL) throws {
        installError = nil
        let artifact = ModelCatalog.qwenBrain
        let destination = ModelCatalog.localURL(for: artifact, fileManager: fileManager)
        _ = try ModelPaths.modelsDirectory(fileManager: fileManager)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        if sourceURL.isFileURL {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } else {
            throw ModelStoreError.importFailed("Source must be a local file URL.")
        }

        refreshStateFromManifest()
    }

    public func removeModel() throws {
        try removeQwenModel()
    }

    private func download(artifact: ModelArtifact) async throws {
        do {
            try await downloadService.download(
                artifact: artifact,
                allowsCellular: allowsCellularDownloads
            )
            refreshStateFromManifest()
        } catch let error as NetworkPolicyError {
            installError = error.localizedDescription
            throw ModelStoreError.cellularNotAllowed
        } catch let error as ModelStoreError {
            installError = error.localizedDescription
            throw error
        } catch {
            installError = error.localizedDescription
            throw ModelStoreError.downloadFailed(error.localizedDescription)
        }
    }

    private func resume(artifact: ModelArtifact) async throws {
        do {
            try await downloadService.resume(
                artifact: artifact,
                allowsCellular: allowsCellularDownloads
            )
            refreshStateFromManifest()
        } catch let error as NetworkPolicyError {
            installError = error.localizedDescription
            throw ModelStoreError.cellularNotAllowed
        } catch {
            installError = error.localizedDescription
            throw ModelStoreError.downloadFailed(error.localizedDescription)
        }
    }

    private func refreshInstallationFromBootstrap() async {
        qwenState = (try? await downloadService.bootstrap(artifact: ModelCatalog.qwenBrain)) ?? .notInstalled
        gemmaState = (try? await downloadService.bootstrap(artifact: ModelCatalog.gemmaVision)) ?? .notInstalled
    }

    private func refreshStateFromManifest() {
        qwenState = (try? downloadService.state(for: ModelCatalog.qwenBrain)) ?? .notInstalled
        gemmaState = (try? downloadService.state(for: ModelCatalog.gemmaVision)) ?? .notInstalled
    }

    private func bytesLabel(for state: ModelInstallState) -> String? {
        guard case let .downloading(written, expected) = state, expected > 0 else { return nil }
        return "\(Self.formatGB(written)) / \(Self.formatGB(expected))"
    }

    private static func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
