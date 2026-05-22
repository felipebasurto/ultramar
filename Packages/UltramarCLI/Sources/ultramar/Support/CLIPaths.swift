import Foundation
import UltramarLLM

enum CLIPaths {
    static let modelsDirEnvKey = "ULTRAMAR_MODELS_DIR"

    static func modelsDirectory(override: String?, fileManager: FileManager = .default) throws -> URL {
        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }
        if let env = ProcessInfo.processInfo.environment[modelsDirEnvKey], !env.isEmpty {
            let url = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }
        return try ModelPaths.modelsDirectory(fileManager: fileManager)
    }

    static func modelFileURL(
        artifact: ModelArtifact,
        modelsDirectory: URL
    ) -> URL {
        modelsDirectory.appendingPathComponent(artifact.filename)
    }

    static func canonicalModelsDirectory(fileManager: FileManager = .default) throws -> URL {
        try ModelPaths.modelsDirectory(fileManager: fileManager)
    }
}
