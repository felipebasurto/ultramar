import Testing
@testable import UltramarLLM

@Test func llamaCppLoggingDefaultsToQuietWithoutEnv() {
    // Documented contract: unset GGML_LOG_LEVEL → suppress all llama.cpp stderr.
    let settings = LlamaCppLogging.parseSettingsForTesting(nil)
    #expect(settings.suppressAll == true)
}

@Test func llamaCppLoggingInfoEnablesVerboseLogs() {
    let settings = LlamaCppLogging.parseSettingsForTesting("info")
    #expect(settings.suppressAll == false)
}
