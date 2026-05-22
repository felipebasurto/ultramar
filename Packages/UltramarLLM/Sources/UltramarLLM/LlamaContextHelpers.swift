import Foundation
import LlamaSwift

enum LlamaContextHelpers {
    static func resetForNewGeneration(
        context: OpaquePointer,
        sampler: UnsafeMutablePointer<llama_sampler>?
    ) {
        llama_memory_clear(llama_get_memory(context), true)
        if let sampler {
            llama_sampler_reset(sampler)
        }
    }
}
