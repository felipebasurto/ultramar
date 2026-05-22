import Foundation
import Testing
@testable import UltramarLLM

@Test func catalogResolveURLMatchesHuggingFacePattern() {
    let artifact = ModelCatalog.qwenBrain
    let url = ModelCatalog.resolveURL(for: artifact)
    #expect(url.absoluteString.contains("huggingface.co"))
    #expect(url.absoluteString.contains(artifact.repo))
    #expect(url.absoluteString.contains(artifact.filename))
}

@Test func catalogExpectedBytesMatchesHuggingFaceContentLength() {
    #expect(ModelCatalog.qwenBrain.expectedBytes == 2_707_514_144)
}

@Test func catalogPinsQwenSHA256() {
    #expect(ModelCatalog.qwenBrain.sha256 == "3c13b4ed335d72170a5b9e65412c890070c49a075767f8e04a475f809f6185d7")
}

@Test func catalogLocalURLUsesQwenFilename() {
    let url = ModelCatalog.localURL(for: ModelCatalog.qwenBrain)
    #expect(url.lastPathComponent == ModelCatalog.qwenBrain.filename)
}

@Test func catalogQwenBrainFilenameMatchesHuggingFaceRepo() {
    #expect(ModelCatalog.qwenBrain.filename == "Qwen.Qwen3.5-4B.Q4_K_M.gguf")
}

@Test func catalogArtifactLookupReturnsKnownArtifacts() {
    #expect(ModelCatalog.artifact(for: ModelCatalog.qwenBrain.id) == ModelCatalog.qwenBrain)
    #expect(ModelCatalog.artifact(for: ModelCatalog.gemmaVision.id) == ModelCatalog.gemmaVision)
    #expect(ModelCatalog.artifact(for: "unknown-artifact") == nil)
}

@Test func catalogGemmaExpectedBytesGreaterThanQwen() {
    #expect(ModelCatalog.gemmaVision.expectedBytes > ModelCatalog.qwenBrain.expectedBytes)
}

/// Same reachability check as `ModelDownloadService` preflight (guards against HTTP 404).
@Test func catalogResolveURLPassesDownloadPreflight() async throws {
    guard TestRunPolicy.networkTestsEnabled else { return }

    let url = ModelCatalog.resolveURL(for: ModelCatalog.qwenBrain)
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    request.timeoutInterval = 60
    let (_, response) = try await URLSession.shared.data(for: request)
    let http = try #require(response as? HTTPURLResponse)
    let ok = (200 ... 299).contains(http.statusCode) || http.statusCode == 302
    #expect(ok, "Catalog URL preflight failed with HTTP \(http.statusCode)")
}
