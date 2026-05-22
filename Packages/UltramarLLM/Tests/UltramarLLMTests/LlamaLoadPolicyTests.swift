import Testing
@testable import UltramarLLM

@Test func llamaLoadPolicyUsesCPULayersOnSimulator() {
    #if targetEnvironment(simulator)
    #expect(LlamaLoadPolicy.gpuLayerCount == 0)
    #else
    #expect(LlamaLoadPolicy.gpuLayerCount == -1)
    #endif
}

@Test func llamaLoadPolicyCapsGenerationTokensOnSimulator() {
    #if targetEnvironment(simulator)
    #expect(LlamaLoadPolicy.maxGenerationTokens == 96)
    #else
    #expect(LlamaLoadPolicy.maxGenerationTokens == 1536)
    #endif
}

@Test func llamaLoadPolicyFinalOnlyUsesSmallerBudgetOnDevice() {
    #if targetEnvironment(simulator)
    #expect(LlamaLoadPolicy.maxGenerationTokens(reasoningMode: .finalOnly) == 96)
    #else
    #expect(LlamaLoadPolicy.maxGenerationTokens(reasoningMode: .finalOnly) == 512)
    #expect(LlamaLoadPolicy.maxGenerationTokens(reasoningMode: .thinking) == 1536)
    #endif
}
