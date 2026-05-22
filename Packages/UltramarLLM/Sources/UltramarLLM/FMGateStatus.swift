import UltramarCore

public struct FMGateStatus: Equatable, Sendable {
    public var osVersionOK: Bool
    public var deviceSupported: Bool
    public var appleIntelligenceEnabled: Bool
    public var localeSupported: Bool
    public var userToggleOn: Bool

    public var isAvailable: Bool {
        osVersionOK && deviceSupported && appleIntelligenceEnabled
            && localeSupported && userToggleOn
    }

    public init(
        osVersionOK: Bool,
        deviceSupported: Bool,
        appleIntelligenceEnabled: Bool,
        localeSupported: Bool,
        userToggleOn: Bool
    ) {
        self.osVersionOK = osVersionOK
        self.deviceSupported = deviceSupported
        self.appleIntelligenceEnabled = appleIntelligenceEnabled
        self.localeSupported = localeSupported
        self.userToggleOn = userToggleOn
    }

    public static let allEnabled = FMGateStatus(
        osVersionOK: true,
        deviceSupported: true,
        appleIntelligenceEnabled: true,
        localeSupported: true,
        userToggleOn: true
    )

    public static let allDisabled = FMGateStatus(
        osVersionOK: false,
        deviceSupported: false,
        appleIntelligenceEnabled: false,
        localeSupported: false,
        userToggleOn: false
    )

    /// All gates pass except the user opt-out toggle (for fallback tests).
    public static let userToggleOff = FMGateStatus(
        osVersionOK: true,
        deviceSupported: true,
        appleIntelligenceEnabled: true,
        localeSupported: true,
        userToggleOn: false
    )

    public func logSnapshot() {
        UltramarLog.fm.info(
            "fm_gate \(UltramarLog.kv(("os", osVersionOK), ("device", deviceSupported), ("ai", appleIntelligenceEnabled), ("locale", localeSupported), ("user_toggle", userToggleOn), ("available", isAvailable)), privacy: .public)"
        )
    }
}
