import Testing
@testable import UltramarLLM

@Test func toolLoopRoutesToQwen() {
    let backend = InferenceRouter.route(task: .toolLoop, fm: .allEnabled)
    #expect(backend == .edgeQwen)
}

@Test func summaryRoutesToFMWhenAvailable() {
    let backend = InferenceRouter.route(task: .summary, fm: .allEnabled)
    #expect(backend == .appleFoundationModels)
}

@Test func summaryFallbackToQwenWhenFMDisabled() {
    let backend = InferenceRouter.route(task: .summary, fm: .userToggleOff)
    #expect(backend == .edgeQwen)
}

@Test func photoAnalysisRoutesToGemma() {
    let backend = InferenceRouter.route(task: .photoAnalysis, fm: .allEnabled)
    #expect(backend == .edgeGemma)
}
