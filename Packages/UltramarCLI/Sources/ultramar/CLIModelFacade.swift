import Foundation
import UltramarCore
import UltramarLLM

@MainActor
enum CLIModelFacade {
    private static let progressInterval: Duration = .seconds(5)

    static func refreshStatus() async -> (qwen: ModelInstallState, gemma: ModelInstallState) {
        let store = ModelStore()
        try? await Task.sleep(for: .milliseconds(100))
        store.refreshInstallationStatus()
        try? await Task.sleep(for: .milliseconds(200))
        return (store.qwenState, store.gemmaState)
    }

    static func download(
        engine: EngineOption,
        allowsCellular: Bool,
        dryRun: Bool
    ) async throws -> DownloadResult {
        guard let artifact = engine.artifact else {
            throw CLIError.invalidFlag("Specify --engine qwen or --engine gemma (not all).")
        }

        let service = ModelDownloadService()
        let initial = try service.state(for: artifact)

        if initial.isInstalled {
            let path = ModelCatalog.localURL(for: artifact).path
            return DownloadResult(
                artifactID: artifact.id,
                path: path,
                bytesOnDisk: fileBytes(at: path),
                alreadyInstalled: true
            )
        }

        if dryRun {
            return DownloadResult(
                artifactID: artifact.id,
                path: ModelCatalog.localURL(for: artifact).path,
                bytesOnDisk: artifact.expectedBytes,
                alreadyInstalled: false,
                dryRun: true
            )
        }

        try await service.download(artifact: artifact, allowsCellular: allowsCellular)

        let final = try await waitForInstall(service: service, artifact: artifact, engine: engine)
        guard final.isInstalled else {
            if case let .failed(message) = final {
                throw CLIError.operationFailed(message)
            }
            throw CLIError.operationFailed("Download did not complete. Check manifest and logs.")
        }

        let path = ModelCatalog.localURL(for: artifact).path
        return DownloadResult(
            artifactID: artifact.id,
            path: path,
            bytesOnDisk: fileBytes(at: path),
            alreadyInstalled: false
        )
    }

    static func remove(engine: EngineOption, yes: Bool, dryRun: Bool) async throws {
        guard let artifact = engine.artifact else {
            throw CLIError.invalidFlag("Specify --engine qwen or --engine gemma (not all).")
        }
        guard yes else {
            throw CLIError.confirmationRequired(
                "Pass --yes to remove \(artifact.displayName).",
                hint: "ultramar models remove --engine \(engine.rawValue) --yes"
            )
        }

        if dryRun {
            return
        }

        let store = ModelStore()
        switch engine {
        case .qwen:
            try store.removeQwenModel()
        case .gemma:
            try store.removeGemmaModel()
        case .all:
            break
        }
    }

    private static func waitForInstall(
        service: ModelDownloadService,
        artifact: ModelArtifact,
        engine: EngineOption
    ) async throws -> ModelInstallState {
        let started = ContinuousClock.now
        let maxWaitMs = 12 * 60 * 60 * 1000
        var lastProgressLog = ContinuousClock.now

        while LogTimer.durationMilliseconds(since: started) < maxWaitMs {
            let state = try service.state(for: artifact)
            switch state {
            case .installed:
                fputs("progress artifact=\(engine.rawValue) complete\n", stderr)
                return state
            case .failed:
                return state
            case .downloading, .verifying, .paused:
                if ContinuousClock.now - lastProgressLog >= progressInterval {
                    logProgress(state: state, engine: engine)
                    lastProgressLog = ContinuousClock.now
                }
            case .notInstalled:
                break
            }
            try await Task.sleep(for: .seconds(1))
        }

        return try service.state(for: artifact)
    }

    private static func logProgress(state: ModelInstallState, engine: EngineOption) {
        if case let .downloading(written, expected) = state, expected > 0 {
            let pct = Int((Double(written) / Double(expected)) * 100)
            fputs(
                "progress artifact=\(engine.rawValue) \(UltramarLog.bytesLabel(written)) / \(UltramarLog.bytesLabel(expected)) (\(pct)%)\n",
                stderr
            )
        } else if state == .verifying {
            fputs("progress artifact=\(engine.rawValue) verifying\n", stderr)
        } else if state == .paused {
            fputs("progress artifact=\(engine.rawValue) paused\n", stderr)
        }
    }

    private static func fileBytes(at path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

struct DownloadResult: Sendable {
    let artifactID: String
    let path: String
    let bytesOnDisk: Int64
    let alreadyInstalled: Bool
    var dryRun: Bool = false
}

enum CLIError: Error, LocalizedError {
    case invalidFlag(String)
    case confirmationRequired(String, hint: String)
    case operationFailed(String)
    case modelNotFound(String, hint: String)

    var errorDescription: String? {
        switch self {
        case .invalidFlag(let message):
            message
        case .confirmationRequired(let message, _):
            message
        case .operationFailed(let message):
            message
        case .modelNotFound(let message, _):
            message
        }
    }

    var hint: String? {
        switch self {
        case .confirmationRequired(_, let hint):
            hint
        case .modelNotFound(_, let hint):
            hint
        default:
            nil
        }
    }
}
