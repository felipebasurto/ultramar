import Foundation
import Testing
@testable import UltramarLLM

@Test func integrityVerifierMatchesKnownSHA256() throws {
    let fileManager = FileManager.default
    let tempURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let payload = Data(repeating: 0xCD, count: 1_048_576)
    try payload.write(to: tempURL)
    defer { try? fileManager.removeItem(at: tempURL) }

    let verifier = ModelIntegrityVerifier()
    let digest = try verifier.sha256Hex(of: tempURL)

    let artifact = ModelArtifact(
        id: "test",
        role: .qwenBrain,
        displayName: "Test",
        repo: "test/repo",
        revision: "main",
        filename: "test.gguf",
        expectedBytes: Int64(payload.count),
        sha256: digest
    )

    try verifier.verify(fileURL: tempURL, artifact: artifact)
}

@Test func integrityVerifierRejectsSHA256Mismatch() throws {
    let fileManager = FileManager.default
    let tempURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try Data("mismatch".utf8).write(to: tempURL)
    defer { try? fileManager.removeItem(at: tempURL) }

    let artifact = ModelArtifact(
        id: "test",
        role: .qwenBrain,
        displayName: "Test",
        repo: "test/repo",
        revision: "main",
        filename: "test.gguf",
        expectedBytes: 1,
        sha256: "deadbeef"
    )

    let verifier = ModelIntegrityVerifier()
    #expect(throws: ModelIntegrityError.self) {
        try verifier.verify(fileURL: tempURL, artifact: artifact)
    }
}

@Test func integrityVerifierAllowsMissingPinnedSHA256() throws {
    let fileManager = FileManager.default
    let tempURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try Data(repeating: 0xAB, count: 2_000_000).write(to: tempURL)
    defer { try? fileManager.removeItem(at: tempURL) }

    let artifact = ModelArtifact(
        id: "test",
        role: .qwenBrain,
        displayName: "Test",
        repo: "test/repo",
        revision: "main",
        filename: "test.gguf",
        expectedBytes: 2_000_000,
        sha256: nil
    )

    try ModelIntegrityVerifier().verify(fileURL: tempURL, artifact: artifact)
}

@Test func minimumAcceptableBytesUsesHalfExpectedOrOneMegabyte() {
    let verifier = ModelIntegrityVerifier()
    let artifact = ModelCatalog.qwenBrain
    let minimum = verifier.minimumAcceptableBytes(for: artifact)
    #expect(minimum >= 1_000_000)
    #expect(minimum <= artifact.expectedBytes)
}
