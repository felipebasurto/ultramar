import Testing
@testable import UltramarCore

@Test func appInfoValues() {
    #expect(AppInfo.displayName == "Ultramar AI")
    #expect(AppInfo.appStoreSubtitle == "Offline travel assistant")
    #expect(AppInfo.bundleIdentifier == "com.felipebasurto.ultramar")
    #expect(AppInfo.companyName == "felipebasurto")
    #expect(AppInfo.version == "0.1.0")
}

@Test func engineRoleDisplayNames() {
    #expect(EngineRole.qwenBrain.displayName == "Qwen 3.5")
    #expect(EngineRole.gemmaVision.displayName == "Gemma 4")
    #expect(EngineRole.none.displayName == "None")
}
