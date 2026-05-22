import SwiftUI
import UltramarCore
import UltramarLLM

@main
struct UltramarAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
