import Foundation
import Network

public enum NetworkPolicyError: Error, LocalizedError {
    case cellularNotAllowed

    public var errorDescription: String? {
        switch self {
        case .cellularNotAllowed:
            "Downloads require Wi‑Fi. Enable “Allow download on cellular” in Brain Model settings, or connect to Wi‑Fi."
        }
    }
}

public struct NetworkPolicyChecker: Sendable {
    public init() {}

    public func assertDownloadAllowed(allowsCellular: Bool) throws {
        guard !allowsCellular else { return }
        guard usesExpensiveInterface() else { return }
        throw NetworkPolicyError.cellularNotAllowed
    }

    private func usesExpensiveInterface() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var expensive = false
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            expensive = path.status == .satisfied && path.usesInterfaceType(.cellular)
            semaphore.signal()
        }
        monitor.start(queue: DispatchQueue(label: "com.felipebasurto.ultramar.network-policy"))
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()
        return expensive
    }
}

public struct DiskSpaceChecker {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func assertSufficientSpace(at directory: URL, requiredBytes: Int64) throws {
        let requiredWithHeadroom = Int64(Double(requiredBytes) * 1.1)
        let available = availableBytes(at: directory)
        guard available > 0, available >= requiredWithHeadroom else {
            throw ModelStoreError.insufficientDiskSpace(
                required: requiredWithHeadroom,
                available: max(available, 0)
            )
        }
    }

    public func availableBytes(at directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? directory.resourceValues(forKeys: keys) else {
            return 0
        }
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let available = values.volumeAvailableCapacity {
            return Int64(available)
        }
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: directory.path),
           let free = attributes[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return 0
    }
}
