import ArgumentParser
import Foundation
import UltramarCore
import UltramarLLM

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check environment, model paths, and Apple Intelligence gates.",
        usage: """
        Examples:
          ultramar doctor
          ultramar doctor --format json
          ultramar doctor --models-dir ~/UltramarModels
        """,
        discussion: """
        Verifies macOS/SDK, models directory, on-disk GGUF files, free disk space, and FM gate status.
        Does not load models into memory.
        """
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let fileManager = FileManager.default
        let modelsDir = try global.resolvedModelsDirectory(fileManager: fileManager)
        let canonicalDir = try CLIPaths.canonicalModelsDirectory(fileManager: fileManager)

        let qwenPath = CLIPaths.modelFileURL(artifact: ModelCatalog.qwenBrain, modelsDirectory: modelsDir)
        let gemmaPath = CLIPaths.modelFileURL(artifact: ModelCatalog.gemmaVision, modelsDirectory: modelsDir)

        let qwenExists = fileManager.fileExists(atPath: qwenPath.path)
        let gemmaExists = fileManager.fileExists(atPath: gemmaPath.path)
        let qwenSize = fileBytes(at: qwenPath)
        let qwenExpectedSHA = ModelCatalog.qwenBrain.sha256 ?? ""
        let qwenActualSHA = qwenExists ? ((try? ModelIntegrityVerifier().sha256Hex(of: qwenPath)) ?? "") : ""
        let qwenVerified = qwenExists
            && qwenSize == ModelCatalog.qwenBrain.expectedBytes
            && !qwenExpectedSHA.isEmpty
            && qwenActualSHA == qwenExpectedSHA

        let freeBytes = freeDiskBytes(at: modelsDir)
        let fm = FMGateDetector.current()

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let fields: [String: JSONValue] = [
            "ok": .bool(true),
            "app_version": .string(AppInfo.version),
            "bundle_id": .string(AppInfo.bundleIdentifier),
            "os_version": .string(osVersion),
            "models_dir": .string(modelsDir.path),
            "canonical_models_dir": .string(canonicalDir.path),
            "qwen_path": .string(qwenPath.path),
            "qwen_present": .bool(qwenExists),
            "qwen_size_bytes": .int64(qwenSize),
            "qwen_expected_bytes": .int64(ModelCatalog.qwenBrain.expectedBytes),
            "qwen_sha256_expected": .string(qwenExpectedSHA),
            "qwen_sha256_actual": .string(qwenActualSHA),
            "qwen_verified": .bool(qwenVerified),
            "gemma_path": .string(gemmaPath.path),
            "gemma_present": .bool(gemmaExists),
            "free_bytes": .int64(freeBytes),
            "fm_available": .bool(fm.isAvailable),
            "fm_os_ok": .bool(fm.osVersionOK),
            "fm_device_supported": .bool(fm.deviceSupported),
            "fm_ai_enabled": .bool(fm.appleIntelligenceEnabled),
            "fm_locale_supported": .bool(fm.localeSupported),
            "fm_user_toggle": .bool(fm.userToggleOn),
        ]

        CLIOutput.print(fields, format: global.format)
    }

    private func freeDiskBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func fileBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
