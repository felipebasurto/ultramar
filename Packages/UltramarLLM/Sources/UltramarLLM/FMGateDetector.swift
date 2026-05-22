import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FMGateDetector {
    public static let userToggleDefaultsKey = "UltramarAI.useAppleIntelligence"

    public static func current() -> FMGateStatus {
        let osVersionOK = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )

        var deviceSupported = false
        var appleIntelligenceEnabled = false
        var localeSupported = false

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let gates = probeFoundationModelGates()
            deviceSupported = gates.deviceSupported
            appleIntelligenceEnabled = gates.appleIntelligenceEnabled
            localeSupported = gates.localeSupported
        }
        #endif

        #if targetEnvironment(simulator)
        deviceSupported = false
        #endif

        let userToggleOn: Bool
        if UserDefaults.standard.object(forKey: userToggleDefaultsKey) == nil {
            userToggleOn = osVersionOK && deviceSupported && appleIntelligenceEnabled && localeSupported
        } else {
            userToggleOn = UserDefaults.standard.bool(forKey: userToggleDefaultsKey)
        }

        return FMGateStatus(
            osVersionOK: osVersionOK,
            deviceSupported: deviceSupported,
            appleIntelligenceEnabled: appleIntelligenceEnabled,
            localeSupported: localeSupported,
            userToggleOn: userToggleOn
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func probeFoundationModelGates() -> (
        deviceSupported: Bool,
        appleIntelligenceEnabled: Bool,
        localeSupported: Bool
    ) {
        switch SystemLanguageModel.default.availability {
        case .available:
            return (true, true, true)
        case .unavailable(.deviceNotEligible):
            return (false, true, true)
        case .unavailable(.appleIntelligenceNotEnabled):
            return (true, false, true)
        case .unavailable(.modelNotReady):
            return (true, true, false)
        case .unavailable:
            return (true, true, false)
        }
    }
    #endif
}
