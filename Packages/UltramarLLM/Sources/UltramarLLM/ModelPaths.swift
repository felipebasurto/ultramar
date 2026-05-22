import Foundation

public enum ModelPaths {
    public static let qwen35FileName = ModelCatalog.qwenBrain.filename
    public static let huggingFaceDownloadURL = ModelCatalog.resolveURL(for: ModelCatalog.qwenBrain)

    public static let backgroundSessionIdentifier = "com.felipebasurto.ultramar.models"

    public static func modelsDirectory(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("UltramarAI", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    public static func manifestURL(fileManager: FileManager = .default) -> URL {
        guard let directory = try? modelsDirectory(fileManager: fileManager) else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("manifest.json")
        }
        return directory.appendingPathComponent("manifest.json")
    }

    public static func resumeDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try modelsDirectory(fileManager: fileManager)
            .appendingPathComponent("resume", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    public static func resumeDataURL(for artifactID: String, fileManager: FileManager = .default) throws -> URL {
        try resumeDirectory(fileManager: fileManager).appendingPathComponent("\(artifactID).resume")
    }

    public static func qwen35ModelURL(fileManager: FileManager = .default) -> URL {
        ModelCatalog.localURL(for: ModelCatalog.qwenBrain, fileManager: fileManager)
    }

    public static func gemma4ModelURL(fileManager: FileManager = .default) -> URL {
        ModelCatalog.localURL(for: ModelCatalog.gemmaVision, fileManager: fileManager)
    }
}
