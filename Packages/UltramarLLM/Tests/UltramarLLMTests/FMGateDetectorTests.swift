import Testing
@testable import UltramarLLM

@Test func fmGateUnavailableOnSimulator() {
    #if targetEnvironment(simulator)
    #expect(FMGateDetector.current().isAvailable == false)
    #else
    // Device availability depends on hardware and Apple Intelligence settings.
    _ = FMGateDetector.current()
    #endif
}
