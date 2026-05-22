import Testing
import UltramarLLM

@Test func toolLoopRoutesToQwen() {
    let backend = InferenceRouter.route(task: .toolLoop, fm: .allEnabled)
    #expect(backend == .edgeQwen)
}

@Test func summaryRoutesToFMWhenAvailable() {
    let backend = InferenceRouter.route(task: .summary, fm: .allEnabled)
    #expect(backend == .appleFoundationModels)
}

@Test func summaryFallbackToQwenWhenFMUserToggleOff() {
    let backend = InferenceRouter.route(task: .summary, fm: .userToggleOff)
    #expect(backend == .edgeQwen)
}
