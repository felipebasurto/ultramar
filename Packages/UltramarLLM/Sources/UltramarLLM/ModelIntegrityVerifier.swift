import CryptoKit
import Foundation
import UltramarCore

public enum ModelIntegrityError: Error, LocalizedError {
    case fileTooSmall(actual: Int64, minimum: Int64)
    case sha256Mismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .fileTooSmall(actual, minimum):
            "Downloaded file is too small (\(actual) bytes; expected at least \(minimum))."
        case let .sha256Mismatch(expected, actual):
            "SHA-256 mismatch. Expected \(expected.prefix(12))…, got \(actual.prefix(12))…."
        }
    }
}

public struct ModelIntegrityVerifier: Sendable {
    private let chunkSize = 1_048_576

    public init() {}

    public func minimumAcceptableBytes(for artifact: ModelArtifact) -> Int64 {
        max(1_000_000, artifact.expectedBytes / 2)
    }

    public func passesSizeCheck(fileURL: URL, artifact: ModelArtifact) -> Bool {
        guard let bytes = try? fileByteCount(at: fileURL) else { return false }
        return bytes >= minimumAcceptableBytes(for: artifact)
    }

    public func verify(fileURL: URL, artifact: ModelArtifact) throws {
        let bytes = try fileByteCount(at: fileURL)
        let pinnedSHA = artifact.sha256?.isEmpty == false
        UltramarLog.models.info(
            "verify_started \(UltramarLog.kv(("artifact", artifact.id), ("bytes", bytes), ("pinned_sha", pinnedSHA)), privacy: .public)"
        )

        let signpost = LogSignpost.begin("models.verify.sha256")
        let start = ContinuousClock.now
        defer { LogSignpost.end("models.verify.sha256", signpost) }

        let minimum = minimumAcceptableBytes(for: artifact)
        guard bytes >= minimum else {
            UltramarLog.models.error(
                "verify_failed \(UltramarLog.kv(("artifact", artifact.id), ("reason", "too_small"), ("bytes", bytes), ("minimum", minimum)), privacy: .public)"
            )
            throw ModelIntegrityError.fileTooSmall(actual: bytes, minimum: minimum)
        }

        guard let expected = artifact.sha256?.lowercased(), !expected.isEmpty else {
            let durationMs = LogTimer.durationMilliseconds(since: start)
            UltramarLog.models.info(
                "verify_passed \(UltramarLog.kv(("artifact", artifact.id), ("duration_ms", durationMs), ("sha_check", "skipped")), privacy: .public)"
            )
            return
        }

        let actual = try sha256Hex(of: fileURL)
        guard actual == expected else {
            UltramarLog.models.error(
                "verify_failed \(UltramarLog.kv(("artifact", artifact.id), ("reason", "sha_mismatch"), ("expected_prefix", UltramarLog.shaPrefix(expected)), ("actual_prefix", UltramarLog.shaPrefix(actual))), privacy: .public)"
            )
            throw ModelIntegrityError.sha256Mismatch(expected: expected, actual: actual)
        }

        let durationMs = LogTimer.durationMilliseconds(since: start)
        UltramarLog.models.info(
            "verify_passed \(UltramarLog.kv(("artifact", artifact.id), ("duration_ms", durationMs)), privacy: .public)"
        )
    }

    public func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func fileByteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
