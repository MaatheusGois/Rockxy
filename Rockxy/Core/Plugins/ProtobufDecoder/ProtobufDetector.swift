import Foundation

// MARK: - ProtobufDetector

nonisolated enum ProtobufDetector {
    static func isLikelyProtobuf(_ data: Data) -> Bool {
        guard let tree = ProtobufHeuristicDecoder.decode(data), !tree.fields.isEmpty else {
            return false
        }
        return true
    }
}
