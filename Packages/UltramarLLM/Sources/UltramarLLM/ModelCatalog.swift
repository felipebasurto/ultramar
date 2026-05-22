import Foundation
import UltramarCore

public struct ModelArtifact: Sendable, Identifiable, Equatable {
    public let id: String
    public let role: EngineRole
    public let displayName: String
    public let repo: String
    public let revision: String
    public let filename: String
    public let expectedBytes: Int64
    /// Pinned via `shasum -a 256` on the release GGUF. When nil, only size checks run.
    public let sha256: String?

    public init(
        id: String,
        role: EngineRole,
        displayName: String,
        repo: String,
        revision: String,
        filename: String,
        expectedBytes: Int64,
        sha256: String?
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.repo = repo
        self.revision = revision
        self.filename = filename
        self.expectedBytes = expectedBytes
        self.sha256 = sha256
    }
}

public enum ModelCatalog {
    /// 2_707_514_144 bytes (HF Content-Length) — pin `sha256` after `shasum -a 256 Qwen.Qwen3.5-4B.Q4_K_M.gguf`.
    public static let qwenBrain = ModelArtifact(
        id: "qwen-brain",
        role: .qwenBrain,
        displayName: "Qwen 3.5 (Brain)",
        repo: "DevQuasar/Qwen.Qwen3.5-4B-GGUF",
        revision: "main",
        filename: "Qwen.Qwen3.5-4B.Q4_K_M.gguf",
        expectedBytes: 2_707_514_144,
        sha256: "3c13b4ed335d72170a5b9e65412c890070c49a075767f8e04a475f809f6185d7"
    )

    /// ~3.43 GB — pin `sha256` after `shasum -a 256 gemma-4-E2B-it-Q4_K_M.gguf`.
    public static let gemmaVision = ModelArtifact(
        id: "gemma-vision",
        role: .gemmaVision,
        displayName: "Gemma 4 (Vision)",
        repo: "lmstudio-community/gemma-4-E2B-it-GGUF",
        revision: "main",
        filename: "gemma-4-E2B-it-Q4_K_M.gguf",
        expectedBytes: 3_430_000_000,
        sha256: nil
    )

    public static func resolveURL(for artifact: ModelArtifact) -> URL {
        URL(
            string: "https://huggingface.co/\(artifact.repo)/resolve/\(artifact.revision)/\(artifact.filename)"
        )!
    }

    public static func localURL(for artifact: ModelArtifact, fileManager: FileManager = .default) -> URL {
        (try? ModelPaths.modelsDirectory(fileManager: fileManager))
            .map { $0.appendingPathComponent(artifact.filename) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(artifact.filename)
    }

    public static func artifact(for id: String) -> ModelArtifact? {
        switch id {
        case qwenBrain.id:
            return qwenBrain
        case gemmaVision.id:
            return gemmaVision
        default:
            return nil
        }
    }
}
