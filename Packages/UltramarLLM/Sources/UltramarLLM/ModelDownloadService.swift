import Foundation
import UltramarCore

@MainActor
public final class ModelDownloadService {
    private let fileManager: FileManager
    private let manifestStore: ModelManifestStore
    private let verifier: ModelIntegrityVerifier
    private let networkPolicy: NetworkPolicyChecker
    private let diskSpace: DiskSpaceChecker
    private let session: ModelDownloadSession
    private var finalizeStart: ContinuousClock.Instant?

    public var onStateChanged: (@MainActor () -> Void)?

    public init(
        fileManager: FileManager = .default,
        manifestStore: ModelManifestStore? = nil,
        verifier: ModelIntegrityVerifier = ModelIntegrityVerifier(),
        networkPolicy: NetworkPolicyChecker = NetworkPolicyChecker(),
        diskSpace: DiskSpaceChecker? = nil,
        session: ModelDownloadSession = .shared
    ) {
        self.fileManager = fileManager
        self.manifestStore = manifestStore ?? ModelManifestStore(fileManager: fileManager)
        self.verifier = verifier
        self.networkPolicy = networkPolicy
        self.diskSpace = diskSpace ?? DiskSpaceChecker(fileManager: fileManager)
        self.session = session
        self.session.setEventHandler { [weak self] event in
            Task { @MainActor in
                await self?.handle(event)
            }
        }
    }

    public func bootstrap(artifact: ModelArtifact = ModelCatalog.qwenBrain) async throws -> ModelInstallState {
        let activeArtifactIDs = await session.reattachExistingTasks()
        let hasActiveDownload = activeArtifactIDs.contains(artifact.id)
            || session.hasActiveDownload(artifactID: artifact.id)
        let context = ModelReconcileContext(
            hasActiveDownload: hasActiveDownload,
            hasResumeData: resumeDataExists(for: artifact.id)
        )
        let manifest = try manifestStore.reconcile(artifact: artifact, verifier: verifier, context: context)
        return manifest[artifact.id]?.state ?? .notInstalled
    }

    public func state(for artifact: ModelArtifact = ModelCatalog.qwenBrain) throws -> ModelInstallState {
        let manifest = try manifestStore.load()
        return manifest[artifact.id]?.state ?? .notInstalled
    }

    public func download(
        artifact: ModelArtifact = ModelCatalog.qwenBrain,
        allowsCellular: Bool
    ) async throws {
        let modelsDirectory = try ModelPaths.modelsDirectory(fileManager: fileManager)
        let freeBytes = diskSpace.availableBytes(at: modelsDirectory)
        let requiredBytes = Int64(Double(artifact.expectedBytes) * 1.1)

        do {
            try networkPolicy.assertDownloadAllowed(allowsCellular: allowsCellular)
            try diskSpace.assertSufficientSpace(at: modelsDirectory, requiredBytes: artifact.expectedBytes)
            try await assertCatalogURLReachable(for: artifact)
        } catch {
            UltramarLog.models.error(
                "download_preflight_failed \(UltramarLog.kv(("artifact", artifact.id), ("error", error.localizedDescription)), privacy: .public)"
            )
            throw error
        }

        UltramarLog.models.info(
            "download_preflight \(UltramarLog.kv(("artifact", artifact.id), ("allows_cellular", allowsCellular), ("free_bytes", freeBytes), ("required_bytes", requiredBytes)), privacy: .public)"
        )

        session.configure(allowsCellularAccess: allowsCellular)
        await session.cancelTasks(for: artifact.id)

        var manifest = try manifestStore.load()
        let previousState = manifest[artifact.id]?.state
        manifest[artifact.id] = ModelManifestEntry(
            artifactID: artifact.id,
            state: .downloading(bytesWritten: 0, bytesExpected: artifact.expectedBytes)
        )
        try manifestStore.save(manifest)
        logManifestTransition(artifactID: artifact.id, from: previousState, to: .downloading(bytesWritten: 0, bytesExpected: artifact.expectedBytes))

        let resumeData: Data?
        let resumed: Bool
        if case .paused = previousState, let data = try? loadResumeData(for: artifact.id) {
            resumeData = data
            resumed = true
        } else {
            try? deleteResumeData(for: artifact.id)
            resumeData = nil
            resumed = false
        }
        if let resumeData {
            session.resumeDownload(artifactID: artifact.id, resumeData: resumeData)
        } else {
            session.startDownload(artifactID: artifact.id, url: ModelCatalog.resolveURL(for: artifact))
        }

        UltramarLog.models.info(
            "download_started \(UltramarLog.kv(("artifact", artifact.id), ("resumed", resumed)), privacy: .public)"
        )
        onStateChanged?()
    }

    public func cancel(artifact: ModelArtifact = ModelCatalog.qwenBrain) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.cancelDownload(artifactID: artifact.id) { [weak self] resumeData in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    do {
                        if let resumeData {
                            try self.saveResumeData(resumeData, for: artifact.id)
                        }
                        var manifest = try self.manifestStore.load()
                        let previousState = manifest[artifact.id]?.state
                        manifest[artifact.id] = ModelManifestEntry(
                            artifactID: artifact.id,
                            state: .paused
                        )
                        try self.manifestStore.save(manifest)
                        self.logManifestTransition(artifactID: artifact.id, from: previousState, to: .paused)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    public func resume(
        artifact: ModelArtifact = ModelCatalog.qwenBrain,
        allowsCellular: Bool
    ) async throws {
        try await download(artifact: artifact, allowsCellular: allowsCellular)
    }

    public func remove(artifact: ModelArtifact = ModelCatalog.qwenBrain) throws {
        let destination = ModelCatalog.localURL(for: artifact, fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try? deleteResumeData(for: artifact.id)

        var manifest = try manifestStore.load()
        let previousState = manifest[artifact.id]?.state
        manifest[artifact.id] = ModelManifestEntry(
            artifactID: artifact.id,
            state: .notInstalled
        )
        try manifestStore.save(manifest)
        logManifestTransition(artifactID: artifact.id, from: previousState, to: .notInstalled)
    }

    public func deletePartial(artifact: ModelArtifact = ModelCatalog.qwenBrain) async throws {
        await session.cancelTasks(for: artifact.id)
        try? deleteResumeData(for: artifact.id)
        var manifest = try manifestStore.load()
        let previousState = manifest[artifact.id]?.state
        manifest[artifact.id] = ModelManifestEntry(
            artifactID: artifact.id,
            state: .notInstalled
        )
        try manifestStore.save(manifest)
        logManifestTransition(artifactID: artifact.id, from: previousState, to: .notInstalled)
    }

    private func handle(_ event: ModelDownloadEvent) async {
        switch event {
        case let .progress(artifactID, bytesWritten, bytesExpected):
            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .downloading(bytesWritten: bytesWritten, bytesExpected: bytesExpected)
            }
        case let .finished(artifactID, temporaryFileURL):
            await finalizeDownload(artifactID: artifactID, temporaryFileURL: temporaryFileURL)
        case let .failed(artifactID, message):
            UltramarLog.models.error(
                "download_failed \(UltramarLog.kv(("artifact", artifactID), ("error", message)), privacy: .public)"
            )
            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .failed(message: message)
            }
        case let .paused(artifactID):
            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .paused
            }
        }
    }

    private func finalizeDownload(artifactID: String, temporaryFileURL: URL) async {
        guard let artifact = ModelCatalog.artifact(for: artifactID) else { return }
        let destination = ModelCatalog.localURL(for: artifact, fileManager: fileManager)

        UltramarLog.models.info(
            "download_finalize_started \(UltramarLog.kv(("artifact", artifactID)), privacy: .public)"
        )
        finalizeStart = ContinuousClock.now

        do {
            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .verifying
            }

            try verifier.verify(fileURL: temporaryFileURL, artifact: artifact)
            _ = try ModelPaths.modelsDirectory(fileManager: fileManager)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryFileURL, to: destination)
            try deleteResumeData(for: artifactID)

            let bytes = try fileByteCount(at: destination)
            let digest = try verifier.sha256Hex(of: destination)

            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .installed(installedAt: .now, bytesOnDisk: bytes, sha256: digest)
            }

            let durationMs = finalizeStart.map { LogTimer.durationMilliseconds(since: $0) } ?? 0
            UltramarLog.models.info(
                "download_installed \(UltramarLog.kv(("artifact", artifactID), ("bytes", bytes), ("sha_prefix", UltramarLog.shaPrefix(digest)), ("duration_ms", durationMs)), privacy: .public)"
            )
        } catch let error as ModelIntegrityError {
            try? fileManager.removeItem(at: temporaryFileURL)
            try? fileManager.removeItem(at: destination)
            UltramarLog.models.error(
                "download_failed \(UltramarLog.kv(("artifact", artifactID), ("error", error.localizedDescription)), privacy: .public)"
            )
            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .failed(message: error.localizedDescription)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryFileURL)
            try? fileManager.removeItem(at: destination)
            UltramarLog.models.error(
                "download_failed \(UltramarLog.kv(("artifact", artifactID), ("error", error.localizedDescription)), privacy: .public)"
            )
            await updateManifest(artifactID: artifactID) { entry in
                entry.state = .failed(message: error.localizedDescription)
            }
        }
        finalizeStart = nil
    }

    private func updateManifest(
        artifactID: String,
        mutate: (inout ModelManifestEntry) -> Void
    ) async {
        do {
            var manifest = try manifestStore.load()
            var entry = manifest[artifactID] ?? ModelManifestEntry(artifactID: artifactID, state: .notInstalled)
            let previousState = entry.state
            mutate(&entry)
            if entry.state.shouldLogManifestTransition(from: previousState) {
                logManifestTransition(artifactID: artifactID, from: previousState, to: entry.state)
            }
            entry.updatedAt = .now
            manifest[artifactID] = entry
            try manifestStore.save(manifest)
            onStateChanged?()
        } catch {
            UltramarLog.models.error(
                "manifest_save_failed \(UltramarLog.kv(("artifact", artifactID), ("error", error.localizedDescription)), privacy: .public)"
            )
        }
    }

    private func logManifestTransition(
        artifactID: String,
        from previousState: ModelInstallState?,
        to newState: ModelInstallState
    ) {
        guard newState.shouldLogManifestTransition(from: previousState) else { return }
        UltramarLog.models.info(
            "manifest_state_changed \(UltramarLog.kv(("artifact", artifactID), ("from", previousState?.logLabel ?? "none"), ("to", newState.logLabel)), privacy: .public)"
        )
    }

    private func saveResumeData(_ data: Data, for artifactID: String) throws {
        let url = try ModelPaths.resumeDataURL(for: artifactID, fileManager: fileManager)
        try data.write(to: url, options: .atomic)
    }

    private func loadResumeData(for artifactID: String) throws -> Data {
        let url = try ModelPaths.resumeDataURL(for: artifactID, fileManager: fileManager)
        return try Data(contentsOf: url)
    }

    private func deleteResumeData(for artifactID: String) throws {
        let url = try ModelPaths.resumeDataURL(for: artifactID, fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func fileByteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func resumeDataExists(for artifactID: String) -> Bool {
        guard let url = try? ModelPaths.resumeDataURL(for: artifactID, fileManager: fileManager) else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    private func assertCatalogURLReachable(for artifact: ModelArtifact) async throws {
        let url = ModelCatalog.resolveURL(for: artifact)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        let ok = (200 ... 299).contains(http.statusCode) || http.statusCode == 302
        guard ok else {
            let host = url.host ?? "unknown"
            throw NSError(
                domain: "UltramarModelDownload",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Model not found at catalog URL (HTTP \(http.statusCode), \(host))"
                ]
            )
        }
    }
}
