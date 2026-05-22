import Foundation
import LlamaSwift

enum LlamaDecodeError: Error {
    case failed
}

enum LlamaBatchHelpers {
    static func decode(token: llama_token, at position: llama_pos, context: OpaquePointer) throws {
        var batch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch) }
        batch.n_tokens = 1
        batch.token[0] = token
        batch.pos[0] = position
        batch.n_seq_id[0] = 1
        if let sequenceIDs = batch.seq_id, let sequenceID = sequenceIDs[0] {
            sequenceID[0] = 0
        }
        batch.logits[0] = 1
        guard llama_decode(context, batch) == 0 else {
            throw LlamaDecodeError.failed
        }
    }
}
