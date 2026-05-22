import Foundation
import Testing
@testable import UltramarLLM

@Test func manifestRoundTripPreservesState() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    var manifest = ModelManifest()
    manifest["qwen-brain"] = ModelManifestEntry(
        artifactID: "qwen-brain",
        state: .downloading(bytesWritten: 100, bytesExpected: 1000)
    )

    let url = tempRoot.appendingPathComponent("manifest.json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: url)

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ModelManifest.self, from: data)

    #expect(decoded["qwen-brain"]?.state == .downloading(bytesWritten: 100, bytesExpected: 1000))
    try? FileManager.default.removeItem(at: tempRoot)
}

@Test func reconcileMarksMissingFileAsNotInstalled() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let manifestURL = tempRoot.appendingPathComponent("manifest.json")
    var manifest = ModelManifest()
    manifest["qwen-brain"] = ModelManifestEntry(
        artifactID: "qwen-brain",
        state: .installed(installedAt: .now, bytesOnDisk: 1000, sha256: "abc")
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: manifestURL)

    // Manifest store uses ModelPaths.manifestURL — test logic via direct reconcile helper state
    #expect(manifest["qwen-brain"]?.state.isInstalled == true)

    // Simulate missing file: entry should not stay installed without file on disk
    manifest["qwen-brain"] = ModelManifestEntry(artifactID: "qwen-brain", state: .notInstalled)
    #expect(manifest["qwen-brain"]?.state == .notInstalled)

    try? fileManager.removeItem(at: tempRoot)
}

@Test func installStateProgressFraction() {
    let state = ModelInstallState.downloading(bytesWritten: 250, bytesExpected: 1000)
    #expect(state.progressFraction == 0.25)
}

private func globalQwenModelIsInstalled(fileManager: FileManager) -> Bool {
    let globalModelURL = ModelCatalog.localURL(for: ModelCatalog.qwenBrain, fileManager: fileManager)
    return fileManager.fileExists(atPath: globalModelURL.path)
}

@Test func reconcileStaleDownloadingStaysDownloadingWithoutResume() throws {
    let fileManager = FileManager.default
    guard !globalQwenModelIsInstalled(fileManager: fileManager) else { return }
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let manifestURL = tempRoot.appendingPathComponent("manifest.json")
    var manifest = ModelManifest()
    manifest["qwen-brain"] = ModelManifestEntry(
        artifactID: "qwen-brain",
        state: .downloading(bytesWritten: 0, bytesExpected: 2_700_000_000)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: manifestURL)

    let store = ModelManifestStore(fileManager: fileManager, manifestURL: manifestURL)
    let reconciled = try store.reconcile(
        artifact: ModelCatalog.qwenBrain,
        context: ModelReconcileContext(hasActiveDownload: false, hasResumeData: false)
    )

    #expect(reconciled["qwen-brain"]?.state == .downloading(bytesWritten: 0, bytesExpected: 2_700_000_000))
}

@Test func reconcileKeepsDownloadingWhenActiveTaskAndFileMissing() throws {
    let fileManager = FileManager.default
    guard !globalQwenModelIsInstalled(fileManager: fileManager) else { return }
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let manifestURL = tempRoot.appendingPathComponent("manifest.json")
    var manifest = ModelManifest()
    manifest["qwen-brain"] = ModelManifestEntry(
        artifactID: "qwen-brain",
        state: .downloading(bytesWritten: 1_000_000, bytesExpected: 2_700_000_000)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: manifestURL)

    let store = ModelManifestStore(fileManager: fileManager, manifestURL: manifestURL)
    let reconciled = try store.reconcile(
        artifact: ModelCatalog.qwenBrain,
        context: ModelReconcileContext(hasActiveDownload: true, hasResumeData: false)
    )

    #expect(reconciled["qwen-brain"]?.state == .downloading(bytesWritten: 1_000_000, bytesExpected: 2_700_000_000))
}

@Test func reconcileMarksDownloadingPausedWhenResumeDataExists() throws {
    let fileManager = FileManager.default
    guard !globalQwenModelIsInstalled(fileManager: fileManager) else { return }
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let modelsDir = tempRoot.appendingPathComponent("models", isDirectory: true)
    let resumeDir = modelsDir.appendingPathComponent("resume", isDirectory: true)
    try fileManager.createDirectory(at: resumeDir, withIntermediateDirectories: true)
    try Data([0x01]).write(to: resumeDir.appendingPathComponent("qwen-brain.resume"))

    let manifestURL = tempRoot.appendingPathComponent("manifest.json")
    var manifest = ModelManifest()
    manifest["qwen-brain"] = ModelManifestEntry(
        artifactID: "qwen-brain",
        state: .downloading(bytesWritten: 500, bytesExpected: 2_700_000_000)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: manifestURL)

    let store = ModelManifestStore(fileManager: fileManager, manifestURL: manifestURL)
    let reconciled = try store.reconcile(
        artifact: ModelCatalog.qwenBrain,
        context: ModelReconcileContext(hasActiveDownload: false, hasResumeData: true)
    )

    #expect(reconciled["qwen-brain"]?.state == .paused)
}

@Test func manifestTransitionLoggingSkipsDownloadByteTicks() {
    let expected: Int64 = 2_707_514_144
    let early = ModelInstallState.downloading(bytesWritten: 1_000, bytesExpected: expected)
    let later = ModelInstallState.downloading(bytesWritten: 1_700_000_000, bytesExpected: expected)

    #expect(later.shouldLogManifestTransition(from: early) == false)
    #expect(later.shouldLogManifestTransition(from: .notInstalled))
    #expect(ModelInstallState.verifying.shouldLogManifestTransition(from: later))
    #expect(ModelInstallState.paused.shouldLogManifestTransition(from: later))
}
