import UIKit
import UltramarCore
import UltramarLLM

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelPaths.backgroundSessionIdentifier else {
            UltramarLog.app.warning(
                "background_session_unknown \(UltramarLog.kv(("identifier", identifier)), privacy: .public)"
            )
            completionHandler()
            return
        }
        UltramarLog.app.info(
            "background_session_wakeup \(UltramarLog.kv(("identifier", identifier)), privacy: .public)"
        )
        ModelDownloadSession.shared.setBackgroundCompletionHandler(completionHandler)
    }
}
