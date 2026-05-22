import Foundation
import UltramarCore

public enum ModelDownloadEvent: Sendable {
    case progress(artifactID: String, bytesWritten: Int64, bytesExpected: Int64)
    case finished(artifactID: String, temporaryFileURL: URL)
    case failed(artifactID: String, message: String)
    case paused(artifactID: String)
}

public final class ModelDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = ModelDownloadSession()

    private var urlSession: URLSession!
    private var allowsCellularAccess = false
    private var eventHandler: (@Sendable (ModelDownloadEvent) -> Void)?
    private var backgroundCompletionHandler: (() -> Void)?

    private struct ActiveDownload {
        var task: URLSessionDownloadTask
        var bytesExpected: Int64
    }

    private var activeDownloads: [String: ActiveDownload] = [:]
    private var lastProgressNotification: [String: Date] = [:]
    private var lastProgressLog: [String: (Date, Int)] = [:]
    private let progressThrottle: TimeInterval = 0.1
    private let progressLogInterval: TimeInterval = 30
    private let lock = NSLock()

    private override init() {
        super.init()
        recreateSession()
    }

    public func setEventHandler(_ handler: @escaping @Sendable (ModelDownloadEvent) -> Void) {
        lock.lock()
        eventHandler = handler
        lock.unlock()
    }

    public func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        backgroundCompletionHandler = handler
        lock.unlock()
        handler()
    }

    public func configure(allowsCellularAccess: Bool) {
        lock.lock()
        let changed = self.allowsCellularAccess != allowsCellularAccess
        self.allowsCellularAccess = allowsCellularAccess
        lock.unlock()
        if changed {
            recreateSession()
        }
    }

    public func startDownload(artifactID: String, url: URL) {
        lock.lock()
        guard activeDownloads[artifactID] == nil else {
            lock.unlock()
            return
        }
        let task = urlSession.downloadTask(with: url)
        task.taskDescription = artifactID
        activeDownloads[artifactID] = ActiveDownload(task: task, bytesExpected: 0)
        lock.unlock()
        task.resume()
    }

    public func resumeDownload(artifactID: String, resumeData: Data) {
        lock.lock()
        guard activeDownloads[artifactID] == nil else {
            lock.unlock()
            return
        }
        let task = urlSession.downloadTask(withResumeData: resumeData)
        task.taskDescription = artifactID
        activeDownloads[artifactID] = ActiveDownload(task: task, bytesExpected: 0)
        lock.unlock()
        task.resume()
    }

    public func cancelDownload(artifactID: String, saveResumeData: @escaping @Sendable (Data?) -> Void) {
        lock.lock()
        guard let active = activeDownloads[artifactID] else {
            lock.unlock()
            saveResumeData(nil)
            return
        }
        lock.unlock()

        active.task.cancel(byProducingResumeData: { data in
            UltramarLog.models.info(
                "download_paused \(UltramarLog.kv(("artifact", artifactID), ("has_resume_data", data != nil)), privacy: .public)"
            )
            saveResumeData(data)
        })
    }

    public func reattachExistingTasks() async -> Set<String> {
        await withCheckedContinuation { continuation in
            urlSession.getAllTasks { tasks in
                var attached = 0
                var artifactIDs: Set<String> = []
                for task in tasks {
                    guard let downloadTask = task as? URLSessionDownloadTask,
                          let artifactID = downloadTask.taskDescription else {
                        continue
                    }
                    artifactIDs.insert(artifactID)
                    self.lock.lock()
                    if self.activeDownloads[artifactID] == nil {
                        self.activeDownloads[artifactID] = ActiveDownload(
                            task: downloadTask,
                            bytesExpected: downloadTask.countOfBytesExpectedToReceive
                        )
                        attached += 1
                    }
                    self.lock.unlock()
                }
                if attached > 0 {
                    UltramarLog.models.info(
                        "session_reattached \(UltramarLog.kv(("active_task_count", attached)), privacy: .public)"
                    )
                }
                continuation.resume(returning: artifactIDs)
            }
        }
    }

    public func hasActiveDownload(artifactID: String) -> Bool {
        lock.lock()
        let isActive = activeDownloads[artifactID] != nil
        lock.unlock()
        return isActive
    }

    private func recreateSession() {
        lock.lock()
        let allowsCellular = allowsCellularAccess
        lock.unlock()

        // Default (foreground) session: reliable delegate progress while the user waits in-app.
        // Background URLSession defers callbacks and breaks progress UI in the simulator.
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = allowsCellular
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.felipebasurto.ultramar.models.download"
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        UltramarLog.models.debug(
            "session_recreated \(UltramarLog.kv(("allows_cellular", allowsCellular), ("mode", "foreground")), privacy: .public)"
        )
    }

    public func cancelTasks(for artifactID: String) async {
        await withCheckedContinuation { continuation in
            urlSession.getAllTasks { tasks in
                for task in tasks where task.taskDescription == artifactID {
                    task.cancel()
                }
                self.removeActive(artifactID: artifactID)
                continuation.resume()
            }
        }
    }

    private func emit(_ event: ModelDownloadEvent) {
        lock.lock()
        let handler = eventHandler
        lock.unlock()
        handler?(event)
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let artifactID = downloadTask.taskDescription else { return }

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            let host = httpResponse.url?.host ?? downloadTask.originalRequest?.url?.host ?? "unknown"
            emit(.failed(artifactID: artifactID, message: "HTTP \(httpResponse.statusCode) (\(host))"))
            removeActive(artifactID: artifactID)
            return
        }

        let temporaryCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gguf")

        do {
            if FileManager.default.fileExists(atPath: temporaryCopy.path) {
                try FileManager.default.removeItem(at: temporaryCopy)
            }
            try FileManager.default.copyItem(at: location, to: temporaryCopy)
            emit(.finished(artifactID: artifactID, temporaryFileURL: temporaryCopy))
        } catch {
            emit(.failed(artifactID: artifactID, message: error.localizedDescription))
        }
        removeActive(artifactID: artifactID)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let artifactID = downloadTask.taskDescription else { return }

        lock.lock()
        let now = Date()
        let last = lastProgressNotification[artifactID] ?? .distantPast
        let shouldEmit = now.timeIntervalSince(last) >= progressThrottle
        if shouldEmit {
            lastProgressNotification[artifactID] = now
        }
        if var active = activeDownloads[artifactID] {
            active.bytesExpected = totalBytesExpectedToWrite
            activeDownloads[artifactID] = active
        }
        lock.unlock()

        guard shouldEmit else { return }
        let expected = Self.plausibleBytesExpected(
            reported: totalBytesExpectedToWrite,
            fallback: Self.expectedBytesFallback(for: artifactID)
        )
        emit(.progress(artifactID: artifactID, bytesWritten: totalBytesWritten, bytesExpected: expected))
        logProgressIfNeeded(
            artifactID: artifactID,
            bytesWritten: totalBytesWritten,
            bytesExpected: expected,
            now: now
        )
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let artifactID = task.taskDescription else { return }
        guard let error else { return }

        if (error as NSError).code == NSURLErrorCancelled {
            emit(.paused(artifactID: artifactID))
        } else {
            emit(.failed(artifactID: artifactID, message: error.localizedDescription))
        }
        removeActive(artifactID: artifactID)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        lock.unlock()
        UltramarLog.models.info(
            "background_events_finished \(UltramarLog.kv(("session_id", ModelPaths.backgroundSessionIdentifier)), privacy: .public)"
        )
        handler?()
    }

    private static func expectedBytesFallback(for artifactID: String) -> Int64 {
        ModelCatalog.artifact(for: artifactID)?.expectedBytes ?? ModelCatalog.qwenBrain.expectedBytes
    }

    private static let minimumPlausibleExpectedBytes: Int64 = 1_000_000

    private static func plausibleBytesExpected(reported: Int64, fallback: Int64) -> Int64 {
        if reported <= 0 { return fallback }
        if reported < minimumPlausibleExpectedBytes, reported < fallback / 100 {
            return fallback
        }
        return reported
    }

    private func logProgressIfNeeded(
        artifactID: String,
        bytesWritten: Int64,
        bytesExpected: Int64,
        now: Date
    ) {
        guard bytesExpected > 0 else { return }

        let catalogExpected = Self.expectedBytesFallback(for: artifactID)
        if bytesExpected < Self.minimumPlausibleExpectedBytes,
           bytesExpected < catalogExpected / 100 {
            UltramarLog.models.warning(
                "download_progress_suspicious \(UltramarLog.kv(("artifact", artifactID), ("bytes_written", bytesWritten), ("bytes_expected", bytesExpected)), privacy: .public)"
            )
            return
        }

        let percent = Int((Double(bytesWritten) / Double(bytesExpected)) * 100)

        lock.lock()
        let previous = lastProgressLog[artifactID]
        let shouldLog: Bool
        if let previous {
            let elapsed = now.timeIntervalSince(previous.0)
            let percentJump = percent - previous.1
            shouldLog = elapsed >= progressLogInterval || percentJump >= 5
        } else {
            shouldLog = true
        }
        if shouldLog {
            lastProgressLog[artifactID] = (now, percent)
        }
        lock.unlock()

        guard shouldLog else { return }
        UltramarLog.models.debug(
            "download_progress \(UltramarLog.kv(("artifact", artifactID), ("bytes_written", bytesWritten), ("bytes_expected", bytesExpected), ("percent", percent)), privacy: .public)"
        )
    }

    private func removeActive(artifactID: String) {
        lock.lock()
        activeDownloads.removeValue(forKey: artifactID)
        lastProgressNotification.removeValue(forKey: artifactID)
        lastProgressLog.removeValue(forKey: artifactID)
        lock.unlock()
    }
}
