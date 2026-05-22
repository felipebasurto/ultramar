import Foundation
import os

public enum LogSignpost {
    private static let logHandle = OSSignposter(
        subsystem: AppInfo.bundleIdentifier,
        category: "perf"
    )

    public static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        logHandle.beginInterval(name)
    }

    public static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        logHandle.endInterval(name, state)
    }
}
