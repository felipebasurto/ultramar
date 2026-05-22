import Foundation

enum LlamaTokenPiece {
    /// Decode bytes returned by `llama_token_to_piece` without deprecated `String(cString:)`.
    static func utf8String(buffer: [CChar], pieceLength: Int32) -> String {
        guard pieceLength > 0 else { return "" }
        let bytes = buffer.prefix(Int(pieceLength)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
